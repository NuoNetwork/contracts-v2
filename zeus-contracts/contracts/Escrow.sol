pragma solidity 0.4.24;

import "./lib/tokens/ERC20.sol";
import "./lib/dappsys/DSThing.sol";
import "./Account.sol";

/**
 * @author Rohit Soni (rohit@nuofox.com)
 */

// TDOD: check if account verification is needed using factory 
contract Escrow is DSNote, DSAuth {

    event LogTransfer(address indexed token, address indexed to, uint value);
    event LogTransferFromAccount(address indexed account, address indexed token, address indexed to, uint value);

    function transfer
    (
        address _token,
        address _to,
        uint _value
    )
        public
        note
        auth
    {
        require(ERC20(_token).transfer(_to, _value), "Escrow::transfer TOKEN_TRANSFER_FAILED");
        emit LogTransfer(_token, _to, _value);
    }

    function transferFromAccount
    (
        address _account,
        address _token,
        address _to,
        uint _value
    )
        public
        note
        auth
    {   
        Account(_account).transferBySystem(_token, _to, _value);
        emit LogTransferFromAccount(_account, _token, _to, _value);
    }

}

// issue with deploying multiple instances of same type in truffle, hence the following two contracts
contract KernelEscrow is Escrow {

}

contract ReserveEscrow is Escrow {
    
}