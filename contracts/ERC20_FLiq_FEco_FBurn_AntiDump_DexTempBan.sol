// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./TimeLockDexTransactions.sol";

/**
* Transações tiram fees
* Fee de liquidez pode ir para todos ou o user ou a empresa(configurável pela empresa) [done: Ailton]
* Fee de ecossistema da empresa(configurável pela empresa)
* Fee de burn. (configurável pela empresa até certo limite)
* Fees totais limitados a 10%
* Upgradeable para próximo token
* Anti whale fees baseado em volume da dex. Configurável até certo limite pela empresa.
* Time lock dex transactions
* Receber fees em BNB ou BUSD (não obrigatório)
*/
contract ERC20FLiqFEcoFBurnAntiDumpDexTempBan is ERC20, ERC20Burnable, Pausable, Ownable, TimeLockDexTransactions {
    using SafeMath for uint256;

    // @dev dead address
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // @dev the fee the ecosystem takes. value uses decimals() as multiplicative factor
    uint256 public ecoSystemFee;

    // @dev which wallet will receive the ecosystem fee
    address public ecoSystemAddress;

    // @dev the fee the liquidity takes. value uses decimals() as multiplicative factor
    uint256 public liquidityFee;

    // @dev which wallet will receive the ecosystem fee. If dead is used, it goes to the msgSender
    address public liquidityAddress;

    // @dev the fee the burn takes. value uses decimals() as multiplicative factor
    uint256 public burnFee;

    // @dev the defauld dex router
    IUniswapV2Router02 public dexRouter;

    address public teamWallet;
    address public lotteryWallet;

    uint256 public liquidityBuyFee = 0;
    uint256 public liquiditySellFee = 0;
    uint256 public burnBuyFee = 0;
    uint256 public burnSellFee = 0;
    uint256 public teamBuyFee = 0;
    uint256 public teamSellFee = 0;
    uint256 public lotteryBuyFee = 0;
    uint256 public lotterySellFee = 0;

    uint256 public totalBuyFee = 0;
    uint256 public totalSellFee = 0;

    uint256 public immutable TOTAL_SUPPLY;

    mapping(address => bool) public isExcludedFromFees;

    address public dexPair;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) public isBlacklisted;

    constructor() ERC20("MafaCoin", "MAFA") {
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);

        ecoSystemAddress = owner();
        liquidityAddress = DEAD_ADDRESS;

        TOTAL_SUPPLY = 1000000000 * (10** decimals());

        _mint(owner(), TOTAL_SUPPLY);
    }

    function afterPreSale() external onlyOwner {
        setLiquidyBuyFee(3);
        setLiquidySellFee(3);
        setBurnBuyFee(1);
        setBurnSellFee(1);
        setTeamBuyFee(1);
        setTeamSellFee(5);
        setLotterySellFee(1);
        setLiquidityAddress(owner());
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != dexPair, "cannot be removed");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    receive() external payable {}

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(isExcludedFromFees[account] != excluded, "Already excluded");
        isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function blacklistAccount(address account, bool blacklisted) external onlyOwner {
        require(isBlacklisted[account] != blacklisted, "Already blacklisted");
        isBlacklisted[account] = blacklisted;

        emit AccountBlacklisted(account, blacklisted);
    }

    function setLiquidityAddress(address recipient) public onlyOwner {
        require(liquidityAddress != recipient, "LP recipient already setted");
        liquidityAddress = recipient;

        emit LiquidityAddressUpdated(recipient);
    }

    function setTeamWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "zero address is not allowed");

        excludeFromFees(_newWallet, true);
        teamWallet = _newWallet;

        emit TeamWalletUpdated(_newWallet);
    }

    function setLotteryWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "zero address is not allowed");
        excludeFromFees(_newWallet, true);
        lotteryWallet = _newWallet;

        emit LotteryWalletUpdated(_newWallet);
    }

    function setLiquidyBuyFee(uint256 newFee) public onlyOwner {
        liquidityBuyFee = newFee;
        _updateTotalBuyFee();

        emit FeeUpdated(newFee, "liquidityBuyFee");
    }

    function setLiquidySellFee(uint256 newFee) public onlyOwner {
        liquiditySellFee = newFee;
        _updateTotalSellFee();

        emit FeeUpdated(newFee, "liquiditySellFee");
    }

    function setBurnBuyFee(uint256 newFee) public onlyOwner {
        burnBuyFee = newFee;
        _updateTotalBuyFee();

        emit FeeUpdated(newFee, "burnBuyFee");
    }

    function setBurnSellFee(uint256 newFee) public onlyOwner {
        burnSellFee = newFee;
        _updateTotalSellFee();

        emit FeeUpdated(newFee, "burnSellFee");
    }

    function setTeamBuyFee(uint256 newFee) public onlyOwner {
        teamBuyFee = newFee;
        _updateTotalBuyFee();

        emit FeeUpdated(newFee, "teamBuyFee");
    }

    function setTeamSellFee(uint256 newFee) public onlyOwner {
        teamSellFee = newFee;
        _updateTotalSellFee();

        emit FeeUpdated(newFee, "teamSellFee");
    }

    function setLotteryBuyFee(uint256 newFee) external onlyOwner {
        lotteryBuyFee = newFee;
        _updateTotalBuyFee();

        emit FeeUpdated(newFee, "lotteryBuyFee");
    }

    function setLotterySellFee(uint256 newFee) public onlyOwner {
        lotterySellFee = newFee;
        _updateTotalSellFee();

        emit FeeUpdated(newFee, "lotterySellFee");
    }

    function _updateTotalBuyFee() internal {
        totalBuyFee = liquidityBuyFee.add(burnBuyFee).add(teamBuyFee).add(lotteryBuyFee);
    }

    function _updateTotalSellFee() internal {
        totalSellFee = liquiditySellFee.add(burnSellFee).add(teamSellFee).add(lotterySellFee);
    }

    function startLiquidity(address router) external onlyOwner {
        require(router != address(0), "zero address is not allowed");

        IUniswapV2Router02 _dexRouter = IUniswapV2Router02(router);

        address _dexPair = IUniswapV2Factory(_dexRouter.factory()).createPair(address(this), _dexRouter.WETH());

        dexRouter = _dexRouter;
        dexPair = _dexPair;

        _setAutomatedMarketMakerPair(_dexPair, true);

        emit LiquidityStarted(router, _dexPair);
    }

    function _swapAndLiquify(uint256 amount) private {
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);

        uint256 initialAmount = address(this).balance;

        _swapTokensForBNB(half);

        uint256 newAmount = address(this).balance.sub(initialAmount);

        _addLiquidity(otherHalf, newAmount);

        emit SwapAndLiquify(half, newAmount, otherHalf);
    }

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

    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{ value: bnbAmount }(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityAddress == DEAD_ADDRESS ? _msgSender() : liquidityAddress,
            block.timestamp.add(300)
        );
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(!isBlacklisted[from], "Address is blacklisted");

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

                if (lotterySellFee > 0) {
                    uint256 tokensToReward = amount.mul(lotterySellFee).div(100);
                    super._transfer(from, lotteryWallet, tokensToReward);
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

                if (lotteryBuyFee > 0) {
                    uint256 tokensToReward = amount.mul(lotteryBuyFee).div(100);
                    super._transfer(from, lotteryWallet, tokensToReward);
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
    event LiquidityAddressUpdated(address indexed liquidityAddress);
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