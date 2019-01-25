pragma solidity 0.4.24;

import "./lib/dappsys/DSThing.sol";
import "./lib/dappsys/DSStop.sol";
import "./lib/tokens/ERC20.sol";
import "./lib/utils/DateTime.sol";
import "./Account.sol";
import "./AccountFactory.sol";
import "./Escrow.sol";
import "./Utils.sol";
import "./Utils2.sol";
import "./ErrorUtils.sol";

/**
 * @author Rohit Soni (rohit@nuofox.com)
 */
// TODO: handling decimals and rounding factors
// TODO: add contract address to hash
contract Reserve is DSStop, DSThing, Utils, Utils2, ErrorUtils {

    Escrow public escrow;
    AccountFactory public accountFactory;
    DateTime public dateTime;
    Config public config;
    uint public deployTimestamp;

    string constant public VERSION = "1.0.0";

    uint public TIME_INTERVAL = 1 days;
    //uint public TIME_INTERVAL = 1 hours;
    
    constructor
    (
        Escrow _escrow,
        AccountFactory _accountFactory,
        DateTime _dateTime,
        Config _config
    ) 
    public 
    {
        escrow = _escrow;
        accountFactory = _accountFactory;
        dateTime = _dateTime;
        config = _config;
        deployTimestamp = now - (4 * TIME_INTERVAL);
    }

    function setEscrow(Escrow _escrow) 
        public 
        note 
        auth
        addressValid(_escrow)
    {
        escrow = _escrow;
    }

    function setAccountFactory(AccountFactory _accountFactory) 
        public 
        note 
        auth
        addressValid(_accountFactory)
    {
        accountFactory = _accountFactory;
    }

    function setDateTime(DateTime _dateTime) 
        public 
        note 
        auth
        addressValid(_dateTime)
    {
        dateTime = _dateTime;
    }

    function setConfig(Config _config) 
        public 
        note 
        auth
        addressValid(_config)
    {
        config = _config;
    }

    struct Order {
        address account;
        address token;
        address byUser;
        uint value;
        uint duration;
        uint expirationTimestamp;
        uint salt;
        uint createdTimestamp;
        bytes32 orderHash;
    }

    bytes32[] public orders;
    mapping (bytes32 => Order) public hashToOrder;
    mapping (bytes32 => bool) public isOrder;
    mapping (address => bytes32[]) public accountToOrders;
    mapping (bytes32 => bool) public cancelledOrders;

    // per day
    mapping (uint => mapping(address => uint)) public deposits;
    mapping (uint => mapping(address => uint)) public withdrawals;
    mapping (uint => mapping(address => uint)) public profits;
    mapping (uint => mapping(address => uint)) public losses;

    mapping (uint => mapping(address => uint)) public reserves;
    mapping (address => uint) public lastReserveRuns;

    mapping (address => mapping(address => uint)) surplus;

    mapping (bytes32 => CumulativeRun) public orderToCumulative;

    struct CumulativeRun {
        uint timestamp;
        uint value;
    }

    modifier onlyAdmin() {
        require(config.isAdminValid(msg.sender), "Reserve::_ INVALID_ADMIN_ACCOUNT");
        _;
    }

    event LogOrderCreated(
        bytes32 indexed orderHash,
        address indexed account,
        address indexed token,
        address byUser,
        uint value,
        uint expirationTimestamp
    );

    event LogOrderCancelled(
        bytes32 indexed orderHash,
        address indexed by
    );

    event LogReserveValuesUpdated(
        address indexed token, 
        uint indexed updatedTill,
        uint reserve,
        uint profit,
        uint loss
    );

    event LogOrderCumulativeUpdated(
        bytes32 indexed orderHash,
        uint updatedTill,
        uint value
    );

    event LogRelease(
        address indexed token,
        address indexed to,
        uint value,
        address by
    );

    event LogLock(
        address indexed token,
        address indexed from,
        uint value,
        uint profit,
        uint loss,
        address by
    );

    event LogLockSurplus(
        address indexed forToken, 
        address indexed token,
        address from,
        uint value
    );

    event LogTransferSurplus(
        address indexed forToken,
        address indexed token,
        address to, 
        uint value
    );
    
    function createOrder
    (
        address[3] _orderAddresses,
        uint[3] _orderValues,
        bytes _signature
    ) 
        public
        note
        onlyAdmin
        whenNotStopped
    {
        Order memory order = _composeOrder(_orderAddresses, _orderValues);
        address signer = _recoverSigner(order.orderHash, _signature);

        if(signer != order.byUser){
            emit LogErrorWithHintBytes32(order.orderHash, "Reserve::createOrder", "SIGNER_NOT_ORDER_CREATOR");
            return;
        }
        
        if(isOrder[order.orderHash]){
            emit LogErrorWithHintBytes32(order.orderHash, "Reserve::createOrder", "ORDER_ALREADY_EXISTS");
            return;
        }

        if(!accountFactory.isAccount(order.account)){
            emit LogErrorWithHintBytes32(order.orderHash, "Reserve::createOrder", "INVALID_ORDER_ACCOUNT");
            return;
        }

        if(!Account(order.account).isUser(signer)){
            emit LogErrorWithHintBytes32(order.orderHash, "Reserve::createOrder", "SIGNER_NOT_AUTHORIZED_WITH_ACCOUNT");
            return;
        }
                
        if(!_isOrderValid(order)) {
            emit LogErrorWithHintBytes32(order.orderHash, "Reserve::createOrder", "INVALID_ORDER_PARAMETERS");
            return;
        }

        if(ERC20(order.token).balanceOf(order.account) < order.value){
            emit LogErrorWithHintBytes32(order.orderHash, "Reserve::createOrder", "INSUFFICIENT_BALANCE_IN_ACCOUNT");
            return;
        }

        escrow.transferFromAccount(order.account, order.token, address(escrow), order.value);
        
        orders.push(order.orderHash);
        hashToOrder[order.orderHash] = order;
        isOrder[order.orderHash] = true;
        accountToOrders[order.account].push(order.orderHash);

        uint dateTimestamp = _getDateTimestamp(now);

        deposits[dateTimestamp][order.token] = add(deposits[dateTimestamp][order.token], order.value);
        
        orderToCumulative[order.orderHash].timestamp = _getDateTimestamp(order.createdTimestamp);
        orderToCumulative[order.orderHash].value = order.value;

        emit LogOrderCreated(
            order.orderHash,
            order.account,
            order.token,
            order.byUser,
            order.value,
            order.expirationTimestamp
        );
    }

    function cancelOrder
    (
        bytes32 _orderHash,
        bytes _signature
    )
        external
        note
        onlyAdmin
    {   
        if(!isOrder[_orderHash]) {
            emit LogErrorWithHintBytes32(_orderHash,"Reserve::createOrder", "ORDER_DOES_NOT_EXIST");
            return;
        }

        if(cancelledOrders[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash,"Reserve::createOrder", "ORDER_ALREADY_CANCELLED");
            return;
        }

        Order memory order = hashToOrder[_orderHash];

        bytes32 cancelOrderHash = _generateActionOrderHash(_orderHash, "CANCEL_RESERVE_ORDER");
        address signer = _recoverSigner(cancelOrderHash, _signature);
        
        if(!Account(order.account).isUser(signer)){
            emit LogErrorWithHintBytes32(_orderHash,"Reserve::createOrder", "SIGNER_NOT_AUTHORIZED_WITH_ACCOUNT");
            return;
        }
        
        doCancelOrder(order);
    }
    
    function processOrder
    (
        bytes32 _orderHash
    ) 
        external 
        note
        onlyAdmin
    {
        if(!isOrder[_orderHash]) {
            emit LogErrorWithHintBytes32(_orderHash,"Reserve::processOrder", "ORDER_DOES_NOT_EXIST");
            return;
        }

        if(cancelledOrders[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash,"Reserve::processOrder", "ORDER_ALREADY_CANCELLED");
            return;
        }

        Order memory order = hashToOrder[_orderHash];

        if(now > _getDateTimestamp(order.expirationTimestamp)) {
            doCancelOrder(order);
        } else {
            emit LogErrorWithHintBytes32(order.orderHash, "Reserve::processOrder", "ORDER_NOT_EXPIRED");
        }
    }

    function doCancelOrder(Order _order) 
        internal
    {   
        uint valueToTransfer = orderToCumulative[_order.orderHash].value;

        if(ERC20(_order.token).balanceOf(escrow) < valueToTransfer){
            emit LogErrorWithHintBytes32(_order.orderHash, "Reserve::doCancel", "INSUFFICIENT_BALANCE_IN_ESCROW");
            return;
        }

        uint nowDateTimestamp = _getDateTimestamp(now);
        cancelledOrders[_order.orderHash] = true;
        withdrawals[nowDateTimestamp][_order.token] = add(withdrawals[nowDateTimestamp][_order.token], valueToTransfer);

        escrow.transfer(_order.token, _order.account, valueToTransfer);
        emit LogOrderCancelled(_order.orderHash, msg.sender);
    }

    function release(address _token, address _to, uint _value) 
        external
        note
        auth
    {   
        require(ERC20(_token).balanceOf(escrow) >= _value, "Reserve::release INSUFFICIENT_BALANCE_IN_ESCROW");
        escrow.transfer(_token, _to, _value);
        emit LogRelease(_token, _to, _value, msg.sender);
    }

    // _value includes profit/loss as well
    function lock(address _token, address _from, uint _value, uint _profit, uint _loss)
        external
        note
        auth
    {   
        require(!(_profit == 0 && _loss == 0), "Reserve::lock INVALID_PROFIT_LOSS_VALUES");
        require(ERC20(_token).balanceOf(_from) >= _value, "Reserve::lock INSUFFICIENT_BALANCE");
            
        if(accountFactory.isAccount(_from)) {
            escrow.transferFromAccount(_from, _token, address(escrow), _value);
        } else {
            Escrow(_from).transfer(_token, address(escrow), _value);
        }
        
        uint dateTimestamp = _getDateTimestamp(now);

        if (_profit > 0){
            profits[dateTimestamp][_token] = add(profits[dateTimestamp][_token], _profit);
        } else if (_loss > 0) {
            losses[dateTimestamp][_token] = add(losses[dateTimestamp][_token], _loss);
        }

        emit LogLock(_token, _from, _value, _profit, _loss, msg.sender);
    }

    // to lock collateral if cannot be liquidated e.g. not enough reserves in kyber
    function lockSurplus(address _from, address _forToken, address _token, uint _value) 
        external
        note
        auth
    {
        require(ERC20(_token).balanceOf(_from) >= _value, "Reserve::lockSurplus INSUFFICIENT_BALANCE_IN_ESCROW");

        Escrow(_from).transfer(_token, address(escrow), _value);
        surplus[_forToken][_token] = add(surplus[_forToken][_token], _value);

        emit LogLockSurplus(_forToken, _token, _from, _value);
    }

    // to transfer surplus collateral out of the system to trade on other platforms and put back in terms of 
    // principal to reserve manually using an account or surplus escrow
    // should work in tandem with lock method when transferring back principal
    function transferSurplus(address _to, address _forToken, address _token, uint _value) 
        external
        note
        auth
    {
        require(ERC20(_token).balanceOf(escrow) >= _value, "Reserve::transferSurplus INSUFFICIENT_BALANCE_IN_ESCROW");
        require(surplus[_forToken][_token] >= _value, "Reserve::transferSurplus INSUFFICIENT_SURPLUS");

        surplus[_forToken][_token] = sub(surplus[_forToken][_token], _value);
        escrow.transfer(_token, _to, _value);

        emit LogTransferSurplus(_forToken, _token, _to, _value);
    }

    function updateReserveValues(address _token, uint _forDays)
        public
        note
        onlyAdmin
    {   
        uint lastReserveRun = lastReserveRuns[_token];

        if (lastReserveRun == 0) {
            lastReserveRun = _getDateTimestamp(deployTimestamp) - TIME_INTERVAL;
        }

        uint nowDateTimestamp = _getDateTimestamp(now);
        uint updatesLeft = ((nowDateTimestamp - TIME_INTERVAL) - lastReserveRun) / TIME_INTERVAL;

        if(updatesLeft == 0) {
            emit LogErrorWithHintAddress(_token, "Reserve::updateReserveValues", "RESERVE_VALUES_UP_TO_DATE");
            return;
        }

        uint counter = updatesLeft;

        if(updatesLeft > _forDays && _forDays > 0) {
            counter = _forDays;
        }

        for (uint i = 0; i < counter; i++) {
            reserves[lastReserveRun + TIME_INTERVAL][_token] = sub(
                sub(
                    add(
                        add(
                            reserves[lastReserveRun][_token],
                            deposits[lastReserveRun + TIME_INTERVAL][_token]
                        ),
                        profits[lastReserveRun + TIME_INTERVAL][_token]
                    ),
                    losses[lastReserveRun + TIME_INTERVAL][_token]
                ),
                withdrawals[lastReserveRun + TIME_INTERVAL][_token]
            );
            lastReserveRuns[_token] = lastReserveRun + TIME_INTERVAL;
            lastReserveRun = lastReserveRuns[_token];
            
            emit LogReserveValuesUpdated(
                _token,
                lastReserveRun,
                reserves[lastReserveRun][_token],
                profits[lastReserveRun][_token],
                losses[lastReserveRun][_token]
            );
            
        }
    }

    function updateOrderCumulativeValueBatch(bytes32[] _orderHashes, uint[] _forDays) 
        public
        note
        onlyAdmin
    {   
        if(_orderHashes.length != _forDays.length) {
            emit LogError("Reserve::updateOrderCumulativeValueBatch", "ARGS_ARRAYLENGTH_MISMATCH");
            return;
        }

        for(uint i = 0; i < _orderHashes.length; i++) {
            updateOrderCumulativeValue(_orderHashes[i], _forDays[i]);
        }
    }

    function updateOrderCumulativeValue
    (
        bytes32 _orderHash, 
        uint _forDays
    ) 
        public
        note
        onlyAdmin 
    {
        if(!isOrder[_orderHash]) {
            emit LogErrorWithHintBytes32(_orderHash, "Reserve::updateOrderCumulativeValue", "ORDER_DOES_NOT_EXIST");
            return;
        }

        if(cancelledOrders[_orderHash]) {
            emit LogErrorWithHintBytes32(_orderHash, "Reserve::updateOrderCumulativeValue", "ORDER_ALREADY_CANCELLED");
            return;
        }
        
        Order memory order = hashToOrder[_orderHash];
        CumulativeRun storage cumulativeRun = orderToCumulative[_orderHash];
        
        uint profitsAccrued = 0;
        uint lossesAccrued = 0;
        uint cumulativeValue = 0;
        uint counter = 0;

        uint lastOrderRun = cumulativeRun.timestamp;
        uint nowDateTimestamp = _getDateTimestamp(now);

        uint updatesLeft = ((nowDateTimestamp - TIME_INTERVAL) - lastOrderRun) / TIME_INTERVAL;

        if(updatesLeft == 0) {
            emit LogErrorWithHintBytes32(_orderHash, "Reserve::updateOrderCumulativeValue", "ORDER_VALUES_UP_TO_DATE");
            return;
        }

        counter = updatesLeft;

        if(updatesLeft > _forDays && _forDays > 0) {
            counter = _forDays;
        }

        for (uint i = 0; i < counter; i++){
            cumulativeValue = cumulativeRun.value;
            lastOrderRun = cumulativeRun.timestamp;

            if(lastReserveRuns[order.token] < lastOrderRun) {
                emit LogErrorWithHintBytes32(_orderHash, "Reserve::updateOrderCumulativeValue", "RESERVE_VALUES_NOT_UPDATED");
                emit LogOrderCumulativeUpdated(_orderHash, cumulativeRun.timestamp, cumulativeRun.value);
                return;
            }

            profitsAccrued = div(
                mul(profits[lastOrderRun + TIME_INTERVAL][order.token], cumulativeValue),
                reserves[lastOrderRun][order.token]
            );
                
            lossesAccrued = div(
                mul(losses[lastOrderRun + TIME_INTERVAL][order.token], cumulativeValue),
                reserves[lastOrderRun][order.token]
            );

            cumulativeValue = sub(add(cumulativeValue, profitsAccrued), lossesAccrued);

            cumulativeRun.timestamp = lastOrderRun + TIME_INTERVAL;
            cumulativeRun.value = cumulativeValue;
        }
        
        emit LogOrderCumulativeUpdated(_orderHash, cumulativeRun.timestamp, cumulativeRun.value);
    }

    function getAllOrders() 
        public
        view 
        returns 
        (
            bytes32[]
        ) 
    {
        return orders;
    }

    function getOrdersForAccount(address _account) 
        public
        view 
        returns 
        (
            bytes32[]
        )
    {
        return accountToOrders[_account];
    }

    function getOrder(bytes32 _orderHash)
        public 
        view 
        returns 
        (
            address _account,
            address _token,
            address _byUser,
            uint _value,
            uint _expirationTimestamp,
            uint _salt,
            uint _createdTimestamp
        )
    {   
        Order memory order = hashToOrder[_orderHash];
        return (
            order.account,
            order.token,
            order.byUser,
            order.value,
            order.expirationTimestamp,
            order.salt,
            order.createdTimestamp
        );
    }

    function _isOrderValid(Order _order)
        internal
        view
        returns (bool)
    {
        if(_order.account == address(0) || _order.byUser == address(0)
         || _order.value <= 0
         || _order.expirationTimestamp <= _order.createdTimestamp || _order.salt <= 0) {
            return false;
        }

        if(isOrder[_order.orderHash]) {
            return false;
        }

        if(cancelledOrders[_order.orderHash]) {
            return false;
        }

        return true;
    }

    function _composeOrder(address[3] _orderAddresses, uint[3] _orderValues)
        internal
        view
        returns (Order _order)
    {
        Order memory order = Order({
            account: _orderAddresses[0],
            token: _orderAddresses[1],
            byUser: _orderAddresses[2],
            value: _orderValues[0],
            createdTimestamp: now,
            duration: _orderValues[1],
            expirationTimestamp: add(now, _orderValues[1]),
            salt: _orderValues[2],
            orderHash: bytes32(0)
        });

        order.orderHash = _generateCreateOrderHash(order);

        return order;
    }

    function _generateCreateOrderHash(Order _order)
        internal
        pure //view
        returns (bytes32 _orderHash)
    {
        return keccak256(
            abi.encodePacked(
 //              address(this),
                _order.account,
                _order.token,
                _order.value,
                _order.duration,
                _order.salt
            )
        );
    }

    function _generateActionOrderHash
    (
        bytes32 _orderHash,
        string _action
    )
        internal
        pure //view
        returns (bytes32 _repayOrderHash)
    {
        return keccak256(
            abi.encodePacked(
//                address(this),
                _orderHash,
                _action
            )
        );
    }

    function _getDateTimestamp(uint _timestamp) 
        internal
        view
        returns (uint)
    {
        // 1 day
        return dateTime.toTimestamp(dateTime.getYear(_timestamp), dateTime.getMonth(_timestamp), dateTime.getDay(_timestamp));
        // 1 hour
        //return dateTime.toTimestamp(dateTime.getYear(_timestamp), dateTime.getMonth(_timestamp), dateTime.getDay(_timestamp), dateTime.getHour(_timestamp));
    } 

}