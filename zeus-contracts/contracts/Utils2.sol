pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ECRecovery.sol";

contract Utils2 {
    using ECRecovery for bytes32;
    
    function _recoverSigner(bytes32 _hash, bytes _signature) 
        internal
        pure
        returns(address _signer)
    {
        return _hash.toEthSignedMessageHash().recover(_signature);
    }

}