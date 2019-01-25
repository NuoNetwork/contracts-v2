pragma solidity 0.4.24;

import "./lib/dappsys/DSThing.sol";
import "./lib/dappsys/DSStop.sol";
import "./lib/utils/Proxy.sol";
import "./Account.sol";
import "./Config.sol";
import "./Utils.sol";

/**
 * @author Rohit Soni (rohit@nuofox.com)
 */

// TODO: should disable account?

contract AccountFactory is DSStop, Utils {
    Config public config;
    mapping (address => bool) public isAccount;
    mapping (address => address[]) public userToAccounts;
    address[] public accounts;

    address public accountMaster;

    constructor
    (
        Config _config, 
        address _accountMaster
    ) 
    public 
    {
        config = _config;
        accountMaster = _accountMaster;
    }

    event LogAccountCreated(address indexed user, address indexed account, address by);

    modifier onlyAdmin() {
        require(config.isAdminValid(msg.sender), "AccountFactory::_ INVALID_ADMIN_ACCOUNT");
        _;
    }

    function setConfig(Config _config) external note auth addressValid(_config) {
        config = _config;
    }

    function setAccountMaster(address _accountMaster) external note auth addressValid(_accountMaster) {
        accountMaster = _accountMaster;
    }

    function newAccount(address _user)
        public
        note
        onlyAdmin
        addressValid(config)
        addressValid(accountMaster)
        whenNotStopped
        returns 
        (
            Account _account
        ) 
    {
        address proxy = new Proxy(accountMaster);
        _account = Account(proxy);
        _account.init(_user, config);

        accounts.push(_account);
        userToAccounts[_user].push(_account);
        isAccount[_account] = true;

        emit LogAccountCreated(_user, _account, msg.sender);
    }
    
    function batchNewAccount(address[] _users) public note onlyAdmin {
        for (uint i = 0; i < _users.length; i++) {
            newAccount(_users[i]);
        }
    }

    function getAllAccounts() public view returns (address[]) {
        return accounts;
    }

    function getAccountsForUser(address _user) public view returns (address[]) {
        return userToAccounts[_user];
    }

}