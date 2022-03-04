//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract TolstaCoin is ERC20PresetFixedSupply, AccessControlEnumerable, Ownable {
    using Address for address;
    
    address private walletTeam = address(0xfC438bCD0f268b91f81b091Dc965D4EA3acB9556);

    constructor() ERC20PresetFixedSupply("Tolsta Coin", "TC", 1000000000 * 10**decimals(), _msgSender()){ 
        // ADD ROLE ADIMIN
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        console.log("contract created");
    }

    function withdraw(address payable to, uint256 amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Transfer to the zero address");
        require(amount <= payable(address(this)).balance, "You are trying to withdraw more funds than available");
        to.transfer(amount);
    }

    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAddress.isContract() , "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }

    // CONTRACT TOKEN DESTROY
    function burnToken(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE){
        uint256 porcentage = _amount * 100 / balanceOf(_msgSender());
        require(porcentage <=  50, "50% maximum burn allowed");
        burn(_amount);
    }

    // TRANSFER TO TEAM WALLET 
    function withdrawTeam(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE)  {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(walletTeam , _amount);
    }

    // GIVEBACK FROM LIQUIDITY 
    function giveback(uint256 _amount) external {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(address(owner()) , _amount);  
    }
}
