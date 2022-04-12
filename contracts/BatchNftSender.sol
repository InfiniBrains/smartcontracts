// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BatchNftSender is Ownable, ReentrancyGuard  {
    address private bankWallet;

    constructor () {
        bankWallet = owner();
    }

    function setBankWallet(address addr) onlyOwner public {
        bankWallet = addr;
        emit SetBankWallet(addr);
    }
    event SetBankWallet(address addr);

    function transferERC721(address token, uint256[] memory ids) nonReentrant external {
        IERC721 nftContract = IERC721(token);
        require(nftContract.isApprovedForAll(_msgSender(),address(this)), "BatchNftSender: not approved");

        for(uint256 i = 0; i < ids.length; i++)
            nftContract.safeTransferFrom(_msgSender(),bankWallet,ids[i]);
        emit TransferERC721(token, _msgSender(), bankWallet, ids);
    }
    event TransferERC721(address token, address form, address to, uint256[] ids);
}