// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WithdrawableOwnable is Ownable, ReentrancyGuard {
    using Address for address;
    using SafeMath for uint256;

    /*
     * @dev Withdraw native token from this contract
     */
    function withdraw(uint256 amount) virtual onlyOwner nonReentrant public {
        uint256 balance = address(this).balance;

        require(amount <= balance, "Withdrawable: you cannot remove this total amount" );

        Address.sendValue(payable(_msgSender()), amount);

        emit Withdraw(_msgSender(), amount);
    }
    event Withdraw(address sender, uint256 value);

    /**
     * @dev Withdraw any ERC20 token from this contract
     * @param tokenAddress ERC20 token to withdraw
     * @param amount the amount desired to remove
     */
    function withdrawERC20(
        address tokenAddress,
        uint256 amount
    ) external virtual nonReentrant onlyOwner {
        require(tokenAddress.isContract(), "Withdrawable: ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);

        uint256 balance = tokenContract.balanceOf(address(this));

        require(amount <= balance, "Withdrawable: you cannot remove this total amount" );

        require(tokenContract.transfer(_msgSender(), amount), "Withdrawable: Fail on transfer");

        emit WithdrawERC20(_msgSender(), tokenAddress, amount);
    }
    event WithdrawERC20(address sender, address token, uint256 value);
}