// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GenericERC20 is ERC20 {
    constructor() ERC20("GenericERC20", "GERC20") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }
}