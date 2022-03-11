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
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract JuniorCoin is ERC20PresetFixedSupply, AccessControlEnumerable, Ownable {
    using Address for address;
    using SafeMath for uint256;

    bool private swapping;
    bool public tradingIsEnabled = false;

    address private walletTeamDev = address(0xfC438bCD0f268b91f81b091Dc965D4EA3acB9556);
    address private walletTeamMkt = address(0x631fDB5b5971275D573b065B8b920B1eDe5c67c4);

    IUniswapV2Router02 public dexRouter;
    address public dexPair;

    uint256 public teamDevBuyFee = 0;
    uint256 public teamMktBuyFee = 0;
    uint256 public teamDevSellFee = 0;
    uint256 public teamMktSellFee = 0;
    uint256 public liquidityFee = 0;
    uint256 public burnFee = 0;
    uint256 public totalBuyFee = 0;
    uint256 public totalSellFee = 0;

    mapping(address => bool) public automatedMarketMakerPairs;

    constructor() ERC20PresetFixedSupply("JuniorCoin", "JRC", 1000000000 * 10**decimals(), _msgSender()){
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
     }

    function afterPreSale() external onlyOwner {
        setTeamDevBuyFee(1);
        setTeamMktBuyFee(1);
        setTeamDevSellFee(5);
        setTeamMktSellFee(5);
        tradingIsEnabled = true;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != dexPair, "cannot be removed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
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

    // TRANSFER TO TEAM DEV
    function withdrawTeamDev(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE)  {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(walletTeamDev , _amount);
    }

        // TRANSFER TO TEAM MARKETING 
    function withdrawTeamMkt(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE)  {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(walletTeamMkt , _amount);
    }

    // GIVEBACK FROM OWNER 
    function giveback(uint256 _amount) external {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(address(owner()) , _amount);  
    }

    function setTeamDevBuyFee(uint256 newFee) public onlyOwner {
        teamDevBuyFee = newFee;
        _updateTotalBuyFee();
    }

    function setTeamMktBuyFee(uint256 newFee) public onlyOwner {
        teamMktBuyFee = newFee;
        _updateTotalBuyFee();
    }

    function setTeamDevSellFee(uint256 newFee) public onlyOwner {
        teamDevSellFee = newFee;
        _updateTotalSellFee();
    }

    function setTeamMktSellFee(uint256 newFee) public onlyOwner {
        teamMktBuyFee = newFee;
        _updateTotalSellFee();
    }

    function _updateTotalBuyFee() internal {
        totalBuyFee = liquidityFee.add(burnFee).add(teamDevBuyFee).add(teamMktBuyFee);
    }

    function _updateTotalSellFee() internal {
        totalSellFee = liquidityFee.add(burnFee).add(teamDevSellFee).add(teamMktSellFee);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "zero address");
        require(to != address(0), "zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(tradingIsEnabled, "Trading not started");

        if (!swapping || !automatedMarketMakerPairs[to] || !automatedMarketMakerPairs[from]){
            swapping = true;
            if (automatedMarketMakerPairs[to]) {
                if (teamDevSellFee > 0) {
                    uint256 tokensToTeam = amount.mul(teamDevSellFee).div(100);
                    super._transfer(from, walletTeamDev, tokensToTeam);
                }

                if (teamMktSellFee > 0) {
                    uint256 tokensToTeam = amount.mul(teamMktSellFee).div(100);
                    super._transfer(from, walletTeamMkt, tokensToTeam);
                }
            } else {
                if (teamDevBuyFee > 0) {
                    uint256 tokensToTeam = amount.mul(teamDevBuyFee).div(100);
                    super._transfer(from, walletTeamDev, tokensToTeam);
                }

                if (teamMktBuyFee > 0) {
                    uint256 tokensToTeam = amount.mul(teamMktBuyFee).div(100);
                    super._transfer(from, walletTeamMkt, tokensToTeam);
                }
            }

            uint256 taxedAmount;
            if(automatedMarketMakerPairs[to]) {
                taxedAmount = amount.sub(amount.mul(totalSellFee).div(100));
            } else {
                taxedAmount = amount.sub(amount.mul(totalBuyFee).div(100));
            }

            console.log("List Fees:");
            console.log(balanceOf(walletTeamDev));
            console.log(balanceOf(walletTeamMkt));
            console.log(taxedAmount);

            super._transfer(from, to, taxedAmount); 

            swapping = false;
        }
    }

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
}
