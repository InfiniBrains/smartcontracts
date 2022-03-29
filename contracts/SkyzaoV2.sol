// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./TimeLockDexTransactions.sol";

contract SkyzaoV2 is ERC20, ERC20Burnable, Pausable, Ownable, TimeLockDexTransactions {
    using SafeMath for uint256;
    using Address for address;

    address liquidityAddress;
    address ecoSystemAddress;
    address public teamWallet;
    address public lotteryWallet;
    address public lpRecipient;
    address public dexPair;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    uint256 ecoSystemFee; 
    uint256 liquidityFee;
    uint256 burnFee;
    uint256 private _maxFee;

    IUniswapV2Router02 public dexRouter;

    uint256 public liquidityBuyFee = 0;
    uint256 public liquiditySellFee = 0;
    uint256 public burnBuyFee = 0;
    uint256 public burnSellFee = 0;
    uint256 public teamBuyFee = 0;
    uint256 public teamSellFee = 0;

    uint256 private constant MAX = type(uint256).max;

    uint256 public totalBuyFee = 0;
    uint256 public totalSellFee = 0;

    uint256 private immutable TOTAL_SUPPLY;

//
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) public isBlacklisted;

    constructor() ERC20("SkyZao", "SKZ") {
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);

        ecoSystemAddress = owner();
        liquidityAddress = DEAD_ADDRESS;

        TOTAL_SUPPLY = 1000000000 * 10**decimals();

        _maxFee = 1000;

        _mint(owner(), TOTAL_SUPPLY);
    }
    
    // Owner's Fee Configuration
    function afterPreSale() external onlyOwner {
        setLiquidyBuyFee(3);
        setLiquidySellFee(3);
        setBurnBuyFee(1);
        setBurnSellFee(1);
        setTeamBuyFee(1);
        setTeamSellFee(5);
        setLpRecipient(owner());

        bool tradingIsEnabled = true;
    }
    
    // Requires that the Dex address is different from the end of the pair
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != dexPair, "cannot be removed");

        _setAutomatedMarketMakerPair(pair, value);
    }
    
    // Function to issue the pair event
    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    receive() external payable {}

    // Requires that the account be fee-free
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(isExcludedFromFees[account] != excluded, "Already excluded");
        isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    // Sets Liquidity Pool Recipient
    function setLpRecipient(address recipient) public onlyOwner {
        require(lpRecipient != recipient, "LP recipient already setted");
        lpRecipient = recipient;

        emit LpRecipientUpdated(recipient);
    }

    // Sets Team Wallet
    function setTeamWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "zero address is not allowed");

        excludeFromFees(_newWallet, true);
        teamWallet = _newWallet;

        emit TeamWalletUpdated(_newWallet);
    }


    // Sets Liquidy Buy Fee
    function setLiquidyBuyFee(uint256 newFee) public onlyOwner {
        liquidityBuyFee = newFee;
        _updateTotalBuyFee();

        emit FeeUpdated(newFee, "liquidityBuyFee");
    }

    // Sets Liquidy Sell Fee
    function setLiquidySellFee(uint256 newFee) public onlyOwner {
        liquiditySellFee = newFee;
        _updateTotalSellFee();

        emit FeeUpdated(newFee, "liquiditySellFee");
    }
    
    // Sets burn buy fee
    function setBurnBuyFee(uint256 newFee) public onlyOwner {
        burnBuyFee = newFee;
        _updateTotalBuyFee();

        emit FeeUpdated(newFee, "burnBuyFee");
    }

    // Sets burn sell fee
    function setBurnSellFee(uint256 newFee) public onlyOwner {
        burnSellFee = newFee;
        _updateTotalSellFee();

        emit FeeUpdated(newFee, "burnSellFee");
    }

    // Sets the team fee on purchase
    function setTeamBuyFee(uint256 newFee) public onlyOwner {
        teamBuyFee = newFee;
        _updateTotalBuyFee();

        emit FeeUpdated(newFee, "teamBuyFee");
    }

    // Sets the team fee on the sale
    function setTeamSellFee(uint256 newFee) public onlyOwner {
        teamSellFee = newFee;
        _updateTotalSellFee();

        emit FeeUpdated(newFee, "teamSellFee");
    }


    // Sums the total of the purchase fees
    function _updateTotalBuyFee() internal {
        totalBuyFee = liquidityBuyFee.add(burnBuyFee).add(teamBuyFee);

        require(totalBuyFee <= _maxFee, "Fees exceeded max limitation");

    }

    // Sums the total sales charges
    function _updateTotalSellFee() internal {
        totalSellFee = liquiditySellFee.add(burnSellFee).add(teamSellFee);

        require(totalSellFee <= _maxFee, "Fees exceeded max limitation");
    }

    // Set address of pair for settlement in dex
    function startLiquidity(address router) external onlyOwner {
        require(router != address(0), "zero address is not allowed");

        IUniswapV2Router02 _dexRouter = IUniswapV2Router02(router);

        address _dexPair = IUniswapV2Factory(_dexRouter.factory()).createPair(address(this), _dexRouter.WETH());

        dexRouter = _dexRouter;
        dexPair = _dexPair;

        _setAutomatedMarketMakerPair(_dexPair, true);

        emit LiquidityStarted(router, _dexPair);
    }

    // Set the swap value of the contract
    function _swapAndLiquify(uint256 amount) private {
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);

        uint256 initialAmount = address(this).balance;

        _swapTokensForBNB(half);

        uint256 newAmount = address(this).balance.sub(initialAmount);

        _addLiquidity(otherHalf, newAmount);

        emit SwapAndLiquify(half, newAmount, otherHalf);
    }

    // Receives the fees in BNB and gives a time lock to those who made the transaction
    function _swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp.add(300)
        );
    }

    // Adds liquidity in the pool between the token and BNB
    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{ value: bnbAmount }(
            address(this),
            tokenAmount,
            0,
            0,
            lpRecipient,
            block.timestamp.add(300)
        );
    }

    // Transfer function
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        bool tradingIsEnabled = true;
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(tradingIsEnabled || (isExcludedFromFees[from] || isExcludedFromFees[to]), "Trading not started");

        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];

        if (excludedAccount) {
            uint256 burnedTokens = balanceOf(DEAD_ADDRESS);
            if (burnedTokens >= TOTAL_SUPPLY.div(2)) {
                setBurnBuyFee(0);
                setBurnSellFee(0);
                emit BurnFeeStopped(burnedTokens, burnBuyFee, burnSellFee);
            }

            super._transfer(from, to, amount);
        } else {
            if (automatedMarketMakerPairs[to]) {
                if (liquiditySellFee > 0) {
                    uint256 tokensToLiquidity = amount.mul(liquiditySellFee).div(100);
                    super._transfer(from, address(this), tokensToLiquidity);
                    _swapAndLiquify(tokensToLiquidity);
                }

                if (burnSellFee > 0) {
                    uint256 burnedTokens = balanceOf(DEAD_ADDRESS);
                    if (burnedTokens >= TOTAL_SUPPLY.div(2)) {
                        setBurnBuyFee(0);
                        setBurnSellFee(0);
                        emit BurnFeeStopped(burnedTokens, burnBuyFee, burnSellFee);
                    }
                    uint256 tokensToBurn = amount.mul(burnSellFee).div(100);
                    super._transfer(from, DEAD_ADDRESS, tokensToBurn);
                }

                if (teamSellFee > 0) {
                    uint256 tokensToTeam = amount.mul(teamSellFee).div(100);
                    super._transfer(from, teamWallet, tokensToTeam);
                }
            } else {
                if (liquidityBuyFee > 0) {
                    uint256 tokensToLiquidity = amount.mul(liquidityBuyFee).div(100);
                    super._transfer(from, address(this), tokensToLiquidity);
                    _swapAndLiquify(tokensToLiquidity);
                }

                if (burnBuyFee > 0) {
                    uint256 burnedTokens = balanceOf(DEAD_ADDRESS);
                    if (burnedTokens >= TOTAL_SUPPLY.div(2)) {
                        setBurnBuyFee(0);
                        setBurnSellFee(0);
                        emit BurnFeeStopped(burnedTokens, burnBuyFee, burnSellFee);
                    }
                    uint256 tokensToBurn = amount.mul(burnBuyFee).div(100);
                    super._transfer(from, DEAD_ADDRESS, tokensToBurn);
                }

                if (teamBuyFee > 0) {
                    uint256 tokensToTeam = amount.mul(teamBuyFee).div(100);
                    super._transfer(from, teamWallet, tokensToTeam);
                }
            }

            uint256 amountMinusFees;
            if (automatedMarketMakerPairs[to]) {
                amountMinusFees = amount.sub(amount.mul(totalSellFee).div(100));
            } else {
                amountMinusFees = amount.sub(amount.mul(totalBuyFee).div(100));
            }
            super._transfer(from, to, amountMinusFees);
        }
    }

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event AccountBlacklisted(address indexed account, bool isBlacklisted);
    event LpRecipientUpdated(address indexed lpRecipient);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(
        uint256 indexed tokensSwapped,
        uint256 indexed bnbReceived,
        uint256 indexed tokensIntoLiqudity
    );
    event BurnFeeStopped(uint256 indexed burnedTokens, uint256 indexed burnBuyFee, uint256 indexed burnSellFee);
    event TeamWalletUpdated(address indexed newWallet);
    event LotteryWalletUpdated(address indexed newWallet);
    event FeeUpdated(uint256 indexed fee, bytes32 indexed feeType);
    event LiquidityStarted(address indexed routerAddress, address indexed pairAddress);
}
