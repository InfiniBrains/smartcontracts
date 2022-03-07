//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract JuniorCoin is ERC20PresetFixedSupply {
    constructor() ERC20PresetFixedSupply("JuniorCoin", "JRC", 1000000000 * 10**decimals(), _msgSender()){ }
}
