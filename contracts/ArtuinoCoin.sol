//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract ArtuinoCoin is ERC20PresetFixedSupply, AccessControlEnumerable {
    using Address for address;
//    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // todo: protect against creation of different dexes
    // 1. protect the token to be used before DEX listing
    //    - create a function that only unpause or unlock the token
    //    - reason: we are going to use BNB funds from public sale as liquidity
    // 2. implement transactions fees
    //    - create sinkholes ex.: burn(total supply approach vs transfer to dead address approach), team(dev, mkt...), liquidity, lottery. Each one with specific address.
    //    - add whitelist for exceptions from fees
    //    - add different fees on buy or sell dex transactions
    //    - exclude liquidity fee or other fees from common transacions
    //    - limit the total fee percent to increase investor protection
    // 3. implement anti dump measures
    //    - if someone wants to dumps a bunch of tokens add a costly fee
    //    - create a funcion the more it wants to dump, more it would be taken
    // 4. anti bot measures
    //    - protect against multiple dex transacions in a small amout of time
    //    - add temp-bans, perma-ban, suspiction detection, awareness time window
    // 5. protect against user misuse
    //    - add withdraw fuctions to give back tokens or native coin for users that send it to the contract
    //    - add native coin, ERC20, ERC721, ERC1155 withdraw functions.
    // 6. increase transparency:
    //    - the contract owner cannot set abusive taxes
    //    - the contract owner cannot pause trading after dex listing
    //    - every set function should emit log
    //    - comment / document all functions
    //    - each contract should be placed in one file. it is preferrable to import openzeppelin and uniswap code and not embed it into one sigle file

    constructor() ERC20PresetFixedSupply("Artuino Coin", "ARC", 1000000000 * 10**decimals(), _msgSender()) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
//        _setupRole(PAUSER_ROLE, _msgSender());

        console.log("contract created");
    }

    function withdraw(address payable to, uint256 amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "transfer to the zero address");
        require(amount <= payable(address(this)).balance, "You are trying to withdraw more funds than available");
        to.transfer(amount);
    }

    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }
}
