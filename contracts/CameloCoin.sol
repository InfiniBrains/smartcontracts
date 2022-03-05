// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract CameloCoin is ERC20PresetFixedSupply{
    constructor() ERC20PresetFixedSupply("CameloCoin", "CMC", 1000000000 * 10**decimals(), _msgSender()){}
}