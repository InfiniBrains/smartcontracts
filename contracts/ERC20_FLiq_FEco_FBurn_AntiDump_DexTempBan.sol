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
* Fee de ecossistema da empresa(configurável pela empresa) [done: Ailton]
* Fee de burn. (configurável pela empresa até certo limite) [done: Ailton]
* Fees totais limitados a 10% [done: Ailton]
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

    uint256 public burnFeeLimit;

    // @dev the defauld dex router
    IUniswapV2Router02 public dexRouter;

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

    function setEcoSystemAddress(address newAddress) public onlyOwner {
        require(ecoSystemAddress != newAddress, "EcoSystem address already setted");
        ecoSystemAddress = newAddress;

        emit EcoSystemAddressUpdated(newAddress);
    }

    function setEcosystemFee(uint256 newFee) public onlyOwner {
        require(newFee.add(liquidityFee).add(burnFee) <= 10, "Fees too high");
        ecoSystemFee = newFee;

        emit EcosystemFeeUpdated(newFee);
    }

    function setLiquidityAddress(address newAddress) public onlyOwner {
        require(liquidityAddress != newAddress, "Liquidity address already setted");
        liquidityAddress = newAddress;

        emit LiquidityAddressUpdated(newAddress);
    }

    function setLiquidityFee(uint256 newFee) public onlyOwner {
        require(newFee.add(ecoSystemFee).add(burnFee) <= 10, "Fees too high");
        liquidityFee = newFee;

        emit LiquidityFeeUpdated(newFee);
    }

    function setBurnFee(uint256 newFee) public onlyOwner {
        require(newFee.add(ecoSystemFee).add(liquidityFee) <= 10, "Fees too high");
        require(newFee <= burnFeeLimit, "New fee higher than burn fee limit");
        burnFee = newFee;

        emit BurnFeeUpdated(newFee);
    }

    function setBurnFeeLimit(uint256 newLimit) public onlyOwner {
        require(newLimit <= 10, "Limit too high");
        burnFeeLimit = newLimit;

        emit BurnFeeLimitUpdated(newLimit);
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

        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];

        if (excludedAccount) {
            super._transfer(from, to, amount);
        } else {
            if (ecoSystemFee > 0) {
                uint256 tokenToEcoSystem = amount.mul(ecoSystemFee).div(100);
                super._transfer(from, ecoSystemAddress, tokenToEcoSystem);
            }

            if (liquidityFee > 0) {
                uint256 tokensToLiquidity = amount.mul(liquidityFee).div(100);
                super._transfer(from, address(this), tokensToLiquidity);
                _swapAndLiquify(tokensToLiquidity);
            }

            uint256 amountMinusFees = amount.sub(ecoSystemFee).sub(liquidityFee);
            super._transfer(from, to, amountMinusFees);
        }
    }

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event LiquidityAddressUpdated(address indexed liquidityAddress);
    event EcoSystemAddressUpdated(address indexed ecoSystemAddress);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(
        uint256 indexed tokensSwapped,
        uint256 indexed bnbReceived,
        uint256 indexed tokensIntoLiqudity
    );
    event EcosystemFeeUpdated(uint256 indexed fee);
    event LiquidityFeeUpdated(uint256 indexed fee);
    event BurnFeeUpdated(uint256 indexed fee);
    event BurnFeeLimitUpdated(uint256 indexed limit);
    event LiquidityStarted(address indexed routerAddress, address indexed pairAddress);
}