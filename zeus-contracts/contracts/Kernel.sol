pragma solidity 0.4.24;

import "./lib/dappsys/DSThing.sol";
import "./lib/dappsys/DSStop.sol";
import "./lib/tokens/ERC20.sol";
import "./AccountFactory.sol";
import "./Account.sol";
import "./Escrow.sol";
import "./Reserve.sol";
import "./KyberConnector.sol";
import "./Utils.sol";
import "./Utils2.sol";
import "./ErrorUtils.sol";

// TODO: handling decimals and rounding factors
// TODO: check for reentrancy vulnerability
// TODO: add contract address to hash

/**
 * @author Rohit Soni (rohit@nuofox.com)
 */
contract Kernel is DSStop, DSThing, Utils, Utils2, ErrorUtils {

    Escrow public escrow;
    AccountFactory public accountFactory;
    Reserve public reserve;
    address public feeWallet;
    Config public config;
    KyberConnector public kyberConnector;
    
    string constant public VERSION = "1.0.0";

    constructor
    (
        Escrow _escrow,
        AccountFactory _accountFactory,
        Reserve _reserve,
        address _feeWallet,
        Config _config,
        KyberConnector _kyberConnector
    ) 
    public 
    {
        escrow = _escrow;
        accountFactory = _accountFactory;
        reserve = _reserve;
        feeWallet = _feeWallet;
        config = _config;
        kyberConnector = _kyberConnector;
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

    function setReserve(Reserve _reserve)
        public 
        note 
        auth
        addressValid(_reserve)
    {
        reserve = _reserve;
    }

    function setConfig(Config _config)
        public 
        note 
        auth
        addressValid(_config)
    {
        config = _config;
    }

    function setKyberConnector(KyberConnector _kyberConnector)
        public 
        note 
        auth
        addressValid(_kyberConnector)
    {
        kyberConnector = _kyberConnector;
    }

    function setFeeWallet(address _feeWallet) 
        public 
        note 
        auth
        addressValid(_feeWallet)
    {
        feeWallet = _feeWallet;
    }

    event LogOrderCreated(
        bytes32 indexed orderHash,
        address indexed account,
        address indexed principalToken,
        address collateralToken,
        address byUser,
        uint principalAmount,
        uint collateralAmount,
        uint premium, // should be in wad?
        uint expirationTimestamp,
        uint fee
    );

    event LogOrderRepaid(
        bytes32 indexed orderHash,
        uint  valueRepaid
    );

    event LogOrderDefaulted(
        bytes32 indexed orderHash,
        string reason
    );

    struct Order {
        address account;
        address byUser;
        address principalToken; 
        address collateralToken;
        uint principalAmount;
        uint collateralAmount;
        uint premium;
        uint duration;
        uint expirationTimestamp;
        uint salt;
        uint fee;
        uint createdTimestamp;
        bytes32 orderHash;
    }

    bytes32[] public orders;
    mapping (bytes32 => Order) public hashToOrder;
    mapping (bytes32 => bool) public isOrder;
    mapping (address => bytes32[]) public accountToOrders;
    
    mapping (bytes32 => bool) public isRepaid;
    mapping (bytes32 => bool) public isDefaulted;

    modifier onlyAdmin() {
        require(config.isAdminValid(msg.sender), "Kernel::_ INVALID_ADMIN_ACCOUNT");
        _;
    }

    // add price to check collateralisation ratio?
    function createOrder
    (
        address[4] _orderAddresses,
        uint[6] _orderValues,
        bytes _signature
    )    
        external
        note
        onlyAdmin
        whenNotStopped
    {   
        Order memory order = _composeOrder(_orderAddresses, _orderValues);
        address signer = _recoverSigner(order.orderHash, _signature);

        if(signer != order.byUser) {
            emit LogErrorWithHintBytes32(order.orderHash, "Kernel::createOrder","SIGNER_NOT_ORDER_CREATOR");
            return;
        }

        if(isOrder[order.orderHash]){
            emit LogErrorWithHintBytes32(order.orderHash, "Kernel::createOrder","ORDER_ALREADY_EXISTS");
            return;
        }

        if(!accountFactory.isAccount(order.account)){
            emit LogErrorWithHintBytes32(order.orderHash, "Kernel::createOrder","INVALID_ORDER_ACCOUNT");
            return;
        }

        if(!Account(order.account).isUser(signer)) {
            emit LogErrorWithHintBytes32(order.orderHash, "Kernel::createOrder","SIGNER_NOT_AUTHORIZED_WITH_ACCOUNT");
            return;
        }

        if(!_isOrderValid(order)){
            emit LogErrorWithHintBytes32(order.orderHash, "Kernel::createOrder","INVALID_ORDER_PARAMETERS");
            return;
        }

        if(ERC20(order.collateralToken).balanceOf(order.account) < order.collateralAmount){
            emit LogErrorWithHintBytes32(order.orderHash, "Kernel::createOrder","INSUFFICIENT_COLLATERAL_IN_ACCOUNT");
            return;
        }

        if(ERC20(order.principalToken).balanceOf(reserve.escrow()) < order.principalAmount){
            emit LogErrorWithHintBytes32(order.orderHash, "Kernel::createOrder","INSUFFICIENT_FUNDS_IN_RESERVE");
            return;
        }
        
        orders.push(order.orderHash);
        hashToOrder[order.orderHash] = order;
        isOrder[order.orderHash] = true;
        accountToOrders[order.account].push(order.orderHash);

        escrow.transferFromAccount(order.account, order.collateralToken, address(escrow), order.collateralAmount);
        reserve.release(order.principalToken, order.account, order.principalAmount);
    
        emit LogOrderCreated(
            order.orderHash,
            order.account,
            order.principalToken,
            order.collateralToken,
            order.byUser,
            order.principalAmount,
            order.collateralAmount,
            order.premium,
            order.expirationTimestamp,
            order.fee
        );
    }

    function getExpectedRepayValue(bytes32 _orderHash) 
        public
        view
        returns (uint)
    {
        Order memory order = hashToOrder[_orderHash];
        uint profits = sub(div(mul(order.principalAmount, order.premium), WAD), order.fee);
        uint valueToRepay = add(order.principalAmount, profits);

        return valueToRepay;
    }

    function repay
    (
        bytes32 _orderHash,
        uint _value,
        bytes _signature
    ) 
        external
        note
        onlyAdmin
    {   
        if(!isOrder[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::repay","ORDER_DOES_NOT_EXIST");
            return;
        }

        if(isRepaid[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::repay","ORDER_ALREADY_REPAID");
            return;
        }

        if(isDefaulted[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::repay","ORDER_ALREADY_DEFAULTED");
            return;
        }
        
        bytes32 repayOrderHash = _generateRepayOrderHash(_orderHash, _value);
        address signer = _recoverSigner(repayOrderHash, _signature);

        Order memory order = hashToOrder[_orderHash];
        
        if(!Account(order.account).isUser(signer)){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::repay","SIGNER_NOT_AUTHORIZED_WITH_ACCOUNT");
            return;
        }

        if(ERC20(order.principalToken).balanceOf(order.account) < _value){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::repay","INSUFFICIENT_BALANCE_IN_ACCOUNT");
            return;
        }

        uint profits = sub(div(mul(order.principalAmount, order.premium), WAD), order.fee);
        uint valueToRepay = add(order.principalAmount, profits);

        if(valueToRepay > _value){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::repay","INSUFFICIENT_REPAYMENT");
            return;
        }

        escrow.transferFromAccount(order.account, order.principalToken, feeWallet, order.fee);
        reserve.lock(order.principalToken, order.account, valueToRepay, profits, 0);
        escrow.transfer(order.collateralToken, order.account, order.collateralAmount);

        isRepaid[order.orderHash] = true;

        emit LogOrderRepaid(
            order.orderHash,
            _value
        );
    }

    function process
    (
        bytes32 _orderHash,
        uint _principalPerCollateral // in WAD
    )
        external
        note
        onlyAdmin
    {   
        if(!isOrder[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::process","ORDER_DOES_NOT_EXIST");
            return;
        }

        if(isRepaid[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::process","ORDER_ALREADY_REPAID");
            return;
        }

        if(isDefaulted[_orderHash]){
            emit LogErrorWithHintBytes32(_orderHash, "Kernel::process","ORDER_ALREADY_DEFAULTED");
            return;
        }

        Order memory order = hashToOrder[_orderHash];

        bool isDefault = false;
        string memory reason = "";

        if(now > order.expirationTimestamp) {
            isDefault = true;
            reason = "DUE_DATE_PASSED";
        } else if (!_isCollateralizationSafe(order, _principalPerCollateral)) {
            isDefault = true;
            reason = "COLLATERAL_UNSAFE";
        }

        isDefaulted[_orderHash] = isDefault;

        if(isDefault) {
            if (!kyberConnector.isTradeFeasible(
                    ERC20(order.collateralToken), 
                    ERC20(order.principalToken),
                    order.collateralAmount)
                )
            {
                reserve.lockSurplus(
                    escrow,
                    order.principalToken,
                    order.collateralToken,
                    order.collateralAmount
                );
                
            } else {
                _performLiquidation(order);
            }
            
            emit LogOrderDefaulted(order.orderHash, reason);
        }

    }

    function _performLiquidation(Order _order) 
        internal
    {
        uint premiumValue = div(mul(_order.principalAmount, _order.premium), WAD);
        uint valueToRepay = add(_order.principalAmount, premiumValue);

        uint principalFromCollateral;
        uint collateralLeft;
        
        (principalFromCollateral, collateralLeft) = kyberConnector.trade(
            escrow,
            ERC20(_order.collateralToken), 
            ERC20(_order.principalToken),
            _order.collateralAmount,
            valueToRepay
        );

        if (principalFromCollateral >= valueToRepay) {
            escrow.transfer(_order.principalToken, feeWallet, _order.fee);

            reserve.lock(
                _order.principalToken,
                escrow,
                sub(principalFromCollateral, _order.fee),
                sub(sub(principalFromCollateral,_order.principalAmount), _order.fee),
                0
            );

            escrow.transfer(_order.collateralToken, _order.account, collateralLeft);

        } else if((principalFromCollateral < valueToRepay) && (principalFromCollateral >= _order.principalAmount)) {
            reserve.lock(
                _order.principalToken,
                escrow,
                principalFromCollateral,
                sub(principalFromCollateral, _order.principalAmount),
                0
            );

        } else {
            reserve.lock(
                _order.principalToken,
                escrow,
                principalFromCollateral,
                0,
                sub(_order.principalAmount, principalFromCollateral)
            );

        }
    }

    function _isCollateralizationSafe(Order _order, uint _principalPerCollateral)
        internal 
        pure
        returns (bool)
    {
        uint totalCollateralValueInPrincipal = div(
            mul(_order.collateralAmount, _principalPerCollateral),
            WAD);
        
        uint premiumValue = div(mul(_order.principalAmount, _order.premium), WAD);
        uint premiumValueBuffer = div(mul(premiumValue, 3), 100); // hardcoded -> can be passed through order?
        uint valueToRepay = add(add(_order.principalAmount, premiumValue), premiumValueBuffer);

        if (totalCollateralValueInPrincipal < valueToRepay) {
            return false;
        }

        return true;
    }

    function _generateRepayOrderHash
    (
        bytes32 _orderHash,
        uint _value
    )
        internal
        pure //view
        returns (bytes32 _repayOrderHash)
    {
        return keccak256(
            abi.encodePacked(
                //address(this),
                _orderHash,
                _value
            )
        );
    }

    function _isOrderValid(Order _order)
        internal
        view
        returns (bool)
    {
        if(_order.account == address(0) || _order.byUser == address(0) 
         || _order.principalToken == address(0) || _order.collateralToken == address(0) 
         || (_order.collateralToken == _order.principalToken)
         || _order.principalAmount <= 0 || _order.collateralAmount <= 0
         || _order.premium <= 0
         || _order.expirationTimestamp <= _order.createdTimestamp || _order.salt <= 0) {
            return false;
        }

        return true;
    }

    function _composeOrder
    (
        address[4] _orderAddresses,
        uint[6] _orderValues
    )
        internal
        view
        returns (Order _order)
    {
        Order memory order = Order({
            account: _orderAddresses[0], 
            byUser: _orderAddresses[1],
            principalToken: _orderAddresses[2],
            collateralToken: _orderAddresses[3],
            principalAmount: _orderValues[0],
            collateralAmount: _orderValues[1],
            premium: _orderValues[2],
            duration: _orderValues[3],
            expirationTimestamp: add(now, _orderValues[3]),
            salt: _orderValues[4],
            fee: _orderValues[5],
            createdTimestamp: now,
            orderHash: bytes32(0)
        });

        order.orderHash = _generateOrderHash(order);
    
        return order;
    }

    function _generateOrderHash(Order _order)
        internal
        pure //view
        returns (bytes32 _orderHash)
    {
        return keccak256(
            abi.encodePacked(
                //address(this),
                _order.account,
                _order.principalToken,
                _order.collateralToken,
                _order.principalAmount,
                _order.collateralAmount,
                _order.premium,
                _order.duration,
                _order.salt,
                _order.fee
            )
        );
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

    function getOrder(bytes32 _orderHash)
        public 
        view 
        returns 
        (
            address _account,
            address _byUser,
            address _principalToken,
            address _collateralToken,
            uint _principalAmount,
            uint _collateralAmount,
            uint _premium,
            uint _expirationTimestamp,
            uint _salt,
            uint _fee,
            uint _createdTimestamp
        )
    {   
        Order memory order = hashToOrder[_orderHash];
        return (
            order.account,
            order.byUser,
            order.principalToken,
            order.collateralToken,
            order.principalAmount,
            order.collateralAmount,
            order.premium,
            order.expirationTimestamp,
            order.salt,
            order.fee,
            order.createdTimestamp
        );
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

}