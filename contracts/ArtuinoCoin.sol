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
    bool paused = false;
    // bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    // Criação do token utilizando o padrão ERC20

    constructor() ERC20PresetFixedSupply("Artuino Coin", "ARC", 1000000000 * 10**decimals(), _msgSender()) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        // _setupRole(PAUSER_ROLE, _msgSender());

        console.log("contract created");
    }

    // Transferência 
    function withdraw(address payable to, uint256 amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "transfer to the zero address");
        require(amount <= payable(address(this)).balance, "You are trying to withdraw more funds than available");
        to.transfer(amount);
    }

    // Transferência de token
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


    // Protect against creation of different dexes
    
    // 1. Protect the token to be used before DEX listing
    // Reason: I assume we are going to use some BNB funds from crowdsale as liquidity

    // 1.1 Create a function that only unpause or unlock the token
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
        require(!paused, "The wallet is paused");
    }

    // 1.2 Protect against creation of different pairs. corner case
    // Cryptocurrencies (moedas base) BTC, ETH, USD
    
    // 1.3 Create a pair at the moment the coin is constructed


    // 2. Implement transactions fees
    // Reason: 
    // 2.1 Create sinkholes ex.: burn(total supply approach vs transfer to dead address approach), team(dev, mkt...), liquidity, lottery. Each one with a specific address. - Partially done, only marketing is used.
    // 2.2 Add whitelist for exceptions from fees
    // 2.3 Add different fees on buy or sell dex transactions
    // 2.4 Exclude liquidity fee or other fees from common transactions
    // 2.5 Limit the total fee percent to increase investor protection
    // 2.6 Reflection fee









}
