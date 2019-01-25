pragma solidity 0.4.24;

import "./lib/kyber/KyberNetworkProxy.sol";
import "./lib/dappsys/DSThing.sol";
import "./lib/tokens/ERC20.sol";
import "./Escrow.sol";
import "./Utils.sol";

contract KyberConnector is DSNote, DSAuth, Utils {
    KyberNetworkProxy public kyber;

    constructor(KyberNetworkProxy _kyber) public {
        kyber = _kyber;
    }

    function setKyber(KyberNetworkProxy _kyber) 
        public
        auth
        addressValid(_kyber)
    {
        kyber = _kyber;
    }

    event LogTrade
    (
        address indexed _from,
        address indexed _srcToken,
        address indexed _destToken,
        uint _srcTokenValue,
        uint _maxDestTokenValue,
        uint _destTokenValue,
        uint _srcTokenValueLeft
    );

    function trade
    (   
        Escrow _escrow,
        ERC20 _srcToken,
        ERC20 _destToken,
        uint _srcTokenValue,
        uint _maxDestTokenValue
    )
        external
        note
        auth
        returns (uint _destTokenValue, uint _srcTokenValueLeft)
    {   
        require(address(_srcToken) != address(_destToken), "KyberConnector::process TOKEN_ADDRS_SHOULD_NOT_MATCH");

        uint _slippageRate;
        (, _slippageRate) = kyber.getExpectedRate(_srcToken, _destToken, _srcTokenValue);

        uint initialSrcTokenBalance = _srcToken.balanceOf(this);

        require(_srcToken.balanceOf(_escrow) >= _srcTokenValue, "KyberConnector::process INSUFFICIENT_BALANCE_IN_ESCROW");
        _escrow.transfer(_srcToken, this, _srcTokenValue);

        require(_srcToken.approve(kyber, 0), "KyberConnector::process SRC_APPROVAL_FAILED");
        require(_srcToken.approve(kyber, _srcTokenValue), "KyberConnector::process SRC_APPROVAL_FAILED");
        
        _destTokenValue = kyber.tradeWithHint(
            _srcToken,
            _srcTokenValue,
            _destToken,
            this,
            _maxDestTokenValue,
            _slippageRate, //0, // no min coversation rate
            address(0), // TODO: check if needed
            ""// bytes(0) // TODO: check if needed // TODO: check zero values for bytes array
        );

        _srcTokenValueLeft = _srcToken.balanceOf(this) - initialSrcTokenBalance;

        require(_transfer(_destToken, _escrow, _destTokenValue), "KyberConnector::process DEST_TOKEN_TRANSFER_FAILED");
        require(_transfer(_srcToken, _escrow, _srcTokenValueLeft), "KyberConnector::process SRC_TOKEN_TRANSFER_FAILED");

        emit LogTrade(_escrow, _srcToken, _destToken, _srcTokenValue, _maxDestTokenValue, _destTokenValue, _srcTokenValueLeft);
    } 

    function getExpectedRate(ERC20 _srcToken, ERC20 _destToken, uint _srcTokenValue) 
        public
        view
        returns(uint _expectedRate, uint _slippageRate)
    {
        (_expectedRate, _slippageRate) = kyber.getExpectedRate(_srcToken, _destToken, _srcTokenValue);
    }

    function isTradeFeasible(ERC20 _srcToken, ERC20 _destToken, uint _srcTokenValue) 
        public
        view
        returns(bool)
    {
        uint slippageRate; 

        (, slippageRate) = getExpectedRate(
            ERC20(_srcToken),
            ERC20(_destToken),
            _srcTokenValue
        );

        return slippageRate == 0 ? false : true;
    }

    function _transfer
    (
        ERC20 _token,
        address _to,
        uint _value
    )
        internal
        returns (bool)
    {
        return _token.transfer(_to, _value);
    }
}