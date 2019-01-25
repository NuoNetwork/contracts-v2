pragma solidity ^0.4.18;

import "../tokens/ERC20.sol";

interface KyberNetworkProxy {

    function maxGasPrice() public view returns(uint);
    function getUserCapInWei(address user) public view returns(uint);
    function getUserCapInTokenWei(address user, ERC20 token) public view returns(uint);
    function enabled() public view returns(bool);
    function info(bytes32 id) public view returns(uint);

    function swapTokenToToken(ERC20 src, uint srcAmount, ERC20 dest, uint minConversionRate) public returns(uint);
    function swapEtherToToken(ERC20 token, uint minConversionRate) public payable returns(uint);
    function swapTokenToEther(ERC20 token, uint srcAmount, uint minConversionRate) public returns(uint);

    function getExpectedRate
    (
        ERC20 src,
        ERC20 dest, 
        uint srcQty
    ) 
        public
        view
        returns 
    (
        uint expectedRate,
        uint slippageRate
    );

    function tradeWithHint
    (
        ERC20 src,
        uint srcAmount,
        ERC20 dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId,
        bytes hint
    )
        public 
        payable 
        returns(uint);
        
}
