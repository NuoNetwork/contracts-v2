pragma solidity 0.4.24;

interface ERC20 {

    function name() public view returns(string);
    function symbol() public view returns(string);
    function decimals() public view returns(uint8);
    function totalSupply() public view returns (uint);

    function balanceOf(address tokenOwner) public view returns (uint balance);
    function allowance(address tokenOwner, address spender) public view returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}