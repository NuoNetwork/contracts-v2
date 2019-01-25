pragma solidity 0.4.24;

contract Utils {

    modifier addressValid(address _address) {
        require(_address != address(0), "Utils::_ INVALID_ADDRESS");
        _;
    }

}