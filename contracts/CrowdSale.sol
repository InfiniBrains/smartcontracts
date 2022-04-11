// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract CrowdSale is Ownable, Pausable {
    using SafeMath for uint256;
    using Address for address;

    // the token to be sold
    IERC20 public _tokenContract;

    // number of tokens already sold
    uint256 public _tokensSold;

    // the time the campaign will start
    uint public _openingTime;

    // the time the campaign will end
    uint public _closingTime;

    // the rate conversion between bnb and the token
    uint256 public _rate;

    constructor() {}

    function setTokenToSell(address tokenContractAddress) public onlyOwner {
        _tokenContract = IERC20(tokenContractAddress);
        emit SetTokenToSell(tokenContractAddress);
    }
    event SetTokenToSell(address tokenContractAddress);

    // ref https://docs.openzeppelin.com/contracts/2.x/crowdsales
    // rate: how much tokens each eth will give
    // supply: the ammout of tokens available in this campaign
    // closingTime: the time the campaign will end
    // openingTime: the time the campaign will start
    function configure(uint256 rate, uint openingTime, uint closingTime) public onlyOwner {
        require(openingTime < closingTime, "openingTime must be lower than closingTime");

        _rate = rate;
        _openingTime = openingTime;
        _closingTime = closingTime;
        _tokensSold = 0;
        emit  Configure(rate, openingTime, closingTime);
    }
    event Configure(uint256 rate, uint openingTime, uint closingTime);

    function configureDates( uint openingTime, uint closingTime) public onlyOwner {
        require(openingTime < closingTime, "openingTime must be lower than closingTime");
        _openingTime = openingTime;
        _closingTime = closingTime;
        emit ConfigureDates(openingTime, closingTime);
    }
    event ConfigureDates( uint openingTime, uint closingTime);

    function configureRate( uint256 rate ) public onlyOwner {
        _rate = rate;
        emit ConfigureRate(rate);
    }
    event ConfigureRate( uint256 rate );

    // how many tokens you will receive for the amount of bnbs
    function bnb2token(uint256 units) public view returns (uint256){
        return units.mul(_rate).div(10**18);
    }

    function buyTokens() public payable whenNotPaused {
        require(block.timestamp <= _closingTime, "Sale has finished");
        require(_openingTime <= block.timestamp, "Sale has not started yet");
        require(msg.value > 0, "You should send money in order to buy tokens");
        uint256 numberOfTokens = bnb2token(msg.value);

        require(supply() >= numberOfTokens, "Contract does not have enough tokens");

        require(_tokenContract.transfer(msg.sender, numberOfTokens), "Some problem with token transfer");

        _tokensSold += numberOfTokens;

        emit Sell(msg.sender, numberOfTokens);
    }
    event Sell(address _buyer, uint256 _amount);

    function withdrawBNB(address to, uint256 amount) onlyOwner public {
        uint256 balance = address(this).balance;
        require(amount<=balance,"Amount greater than the balance");
        Address.sendValue(payable(to), amount);
    }

    /**
     * @dev Withdraw any ERC20 token from this contract
     * @param tokenAddress ERC20 token to withdraw
     * @param to receiver address
     * @param amount amount to withdraw
     */
    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyOwner {
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }

    function totalBalance() external view returns(uint256) {
        return payable(address(this)).balance;
    }

    function supply() public view returns (uint256) {
        return _tokenContract.balanceOf(address(this));
    }

//    function endSale() public onlyOwner {
//        require(
//            _tokenContract.transfer(owner(), _tokenContract.balanceOf(address(this))),
//            "Unable to transfer tokens to admin"
//        );
//        // destroy contract and send ethers to the owner
//        // https://solidity-by-example.org/hacks/self-destruct/
////        selfdestruct(payable(owner()));
//    }

    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    function unPause() public onlyOwner whenPaused {
        _unpause();
    }

    function isPaused() public view returns (bool) {
        return paused();
    }
}