//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract FabricaDeGeniosCoin is ERC20PresetMinterPauser {
    constructor() ERC20PresetMinterPauser("Fabrica de Genios Coin", "FGC") {
        console.log("contract created");
    }
}
