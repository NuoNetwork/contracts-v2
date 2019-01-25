pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";

contract TestToken is StandardToken {
    string public name = "Test Token";
    string public symbol = "TTT";
    uint8 public decimals = 18;
    // max uint value possible
    uint public INITIAL_SUPPLY = (10**24);

    constructor() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
    }
}