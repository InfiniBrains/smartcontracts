// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WithdrawableOwnable is Ownable, ReentrancyGuard {
    using Address for address;
    using SafeMath for uint256;

    /*
     * @dev Withdraw native token from this contract
     * @param amount the amount of tokens you want to withdraw
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

    /**
     * @dev Withdraw any ERC721 token from this contract
     * @param tokenAddress ERC721 token to withdraw
     * @param tokenIds IDs of the NFTs to withdraw
     */
    function withdrawERC721(
        address tokenAddress,
        uint256[] memory tokenIds
    ) external virtual onlyOwner nonReentrant {
        require(tokenAddress.isContract(), "ERC721 token address must be a contract");

        IERC721 tokenContract = IERC721(tokenAddress);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenContract.ownerOf(tokenIds[i]) == address(this),
                "This contract doesn't own the NFT you are trying to withdraw"
            );
            tokenContract.safeTransferFrom(address(this), _msgSender(), tokenIds[i]);
        }
        emit WithdrawERC721(tokenAddress, tokenIds);
    }
    event WithdrawERC721(address tokenAddress, uint256[] tokenIds);

    /**
     * @dev Withdraw any ERC1155 token from this contract
     * @param tokenAddress ERC1155 token to withdraw
     * @param id ID of the token to withdraw
     * @param amount amount to withdraw
     */
    function withdrawERC1155(
        address tokenAddress,
        uint256 id,
        uint256 amount
    ) external virtual onlyOwner nonReentrant {
        require(tokenAddress.isContract(), "ERC1155 token address must be a contract");

        IERC1155 tokenContract = IERC1155(tokenAddress);
        require(
            tokenContract.balanceOf(address(this), id) >= amount,
            "this contract doesn't own the amount of tokens to withdraw"
        );

        tokenContract.safeTransferFrom(address(this), _msgSender(), id, amount, "");
    }
    event WithdrawERC1155(address tokenAddress, uint256 id, uint256 amount);
}