//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract FabricaDeGeniosCoin is ERC20PresetFixedSupply, AccessControlEnumerable {
    using Address for address;
//    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // todo: protect against creation of different dex usages
    // 1. protect the token to be used before DEX listing
    // 2. implement transactions fees
    //    - create sinkholes ex.: burn(total supply approach, transfer approach), team(dev, mkt...), liquidity, lottery
    //    - add whitelist for exceptions from fees
    //    - add different fees on buy or sell dex transactions
    //    - exclude liquidity fee or other fees from common transacions
    //    - limit the total fee percent to increase investor protection
    // 3. implement anti dump measures
    //    - if someone wants to dumps a bunch of tokens add a costly fee
    // 4. anti bot measures
    //    - protect against multiple dex transacions in a small amout of time
    //    - add temp-bans, perma-ban, suspiction detection, attention time window
    // 5. protect against user misuse
    //    - add withdraw fuctions to give back tokens or native coin for users that send it to the contract

    constructor() ERC20PresetFixedSupply("Fabrica de Genios Coin", "FGC", 1000000000 * 10**decimals(), _msgSender()) {
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
