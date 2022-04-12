// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./TimeLockTransactions.sol";
import "./WithdrawableOwnable.sol";

/**
* Features:
*   Liquidity fee can go to all company. (Company configurable)
*   Enterprise ecosystem fee. (Company configurable)
*   Burn rate. (Company configurable up to a certain limit)
*   Total fees capped.
*   Upgradable to next token.
*   Dex volume based anti-whale fees. (Configurable to a certain extent by the company)
*   Time lock dex transactions.
*   Prevent people from creating peers without company authorization.
*/
contract ERC20FLiqFEcoFBurnAntiDumpDexTempBan is ERC20, Ownable, TimeLockTransactions, WithdrawableOwnable {
    using SafeMath for uint256;
    using Address for address;

    // @dev dead address
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // @dev the fee the ecosystem takes. value uses decimals() as multiplicative factor
    uint256 public ecoSystemFee = 0;

    // @dev which wallet will receive the ecosystem fee
    address public ecoSystemAddress;

    // @dev the fee the liquidity takes. value uses decimals() as multiplicative factor
    uint256 public liquidityFee = 5 * 10**16; // 5%

    // @dev which wallet will receive the ecosystem fee. If dead is used, it goes to the msgSender
    address public liquidityAddress;

    // @dev the fee the burn takes. value uses decimals() as multiplicative factor
    uint256 public burnFee = 0; // 0%

    // @dev the max value of the ordinary fees sum
    uint256 public constant FEE_LIMIT = 2 * 10**17; // 20%

    // @dev the defauld dex router
    IUniswapV2Router02 public dexRouter;

    // @dev the dex factory address
    address public uniswapFactoryAddress;

    // @dev just to simplify to the user, the total fees
    uint256 public totalFees = 0;

    // @dev antidump mechanics
    uint256 public antiDumpThreshold = 5 * 10**15; // 0.5%

    // @dev antidump mechanics
    uint256 public antiDumpFee = 25 * 10**16; // 25%

    // @dev antidump mechanics
    uint256 public constant ANTI_DUMP_THRESHOLD_LIMIT = 1 * 10**15; // 0.1%

    // @dev antidump mechanics the total max value of the extra fees
    uint256 public constant ANTI_DUMP_FEE_LIMIT = 25 * 10**16; // 25%

    // @dev the total max value of the fees
    uint256 public numTokensSellToAddToLiquidity = 0;

    // @dev mapping of excluded from fees elements
    mapping(address => bool) public isExcludedFromFees;

    // @dev the default dex pair
    address public dexPair;

    // @dev what pairs are allowed to work in the token
    mapping(address => bool) public automatedMarketMakerPairs;

    constructor(string memory name, string memory symbol, uint256 totalSupply) ERC20(name, symbol) {
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);

        ecoSystemAddress = owner();
        liquidityAddress = DEAD_ADDRESS;

        _mint(owner(), totalSupply);

        numTokensSellToAddToLiquidity = totalSupply.div(10**6); // 0.000001% of total supply

        // Create a uniswap pair for this new token
        dexRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // mainnet
//        dexRouter = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // testnet
        uniswapFactoryAddress = address(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73); // mainnet
//        uniswapFactoryAddress = address(0x6725F303b657a9451d8BA641348b6761A6CC7a17); // testnet

        dexPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), dexRouter.WETH());
        _setAutomatedMarketMakerPair(dexPair, true);

        _updateTotalFee();

        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[DEAD_ADDRESS] = true;

        emit ExcludeFromFees(owner(), true);
        emit ExcludeFromFees(address(this), true);
        emit ExcludeFromFees(DEAD_ADDRESS, true);
    }

    function setMinNumTokensSellToAddToLiquidity(uint256 newLimit) external onlyOwner {
        require(newLimit >= totalSupply().div(10**6), "new limit is too low");
        numTokensSellToAddToLiquidity = newLimit;
        emit SetMinNumTokensSellToAddToLiquidity(newLimit);
    }
    event SetMinNumTokensSellToAddToLiquidity(uint256 newLimit);

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != dexPair, "default pair cannot be changed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    // @dev create and add a new pair for a given token
    function addNewPair(address tokenAddress) external onlyOwner returns (address np) {
        address newPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), tokenAddress);
        _setAutomatedMarketMakerPair(newPair, true);
        emit AddNewPair(tokenAddress, newPair);
        return newPair;
    }
    event AddNewPair(address indexed tokenAddress, address indexed newPair);

    receive() external payable {}

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(isExcludedFromFees[account] != excluded, "Already set");
        isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function checkFeesChanged(uint256 _oldFee, uint256 _newFee) internal view {
        uint256 _fees = ecoSystemFee.add(liquidityFee).add(burnFee).add(_newFee).sub(_oldFee);
        require(_fees <= FEE_LIMIT, "Fees exceeded max limitation");
    }

    function setEcoSystemAddress(address newAddress) public onlyOwner {
        require(ecoSystemAddress != newAddress, "EcoSystem address already setted");
        ecoSystemAddress = newAddress;
        emit EcoSystemAddressUpdated(newAddress);
    }

    function setEcosystemFee(uint256 newFee) public onlyOwner {
        checkFeesChanged(ecoSystemFee, newFee);
        ecoSystemFee = newFee;
        _updateTotalFee();
        emit EcosystemFeeUpdated(newFee);
    }

    function setLiquidityAddress(address newAddress) public onlyOwner {
        require(liquidityAddress != newAddress, "Liquidity address already setted");
        liquidityAddress = newAddress;
        emit LiquidityAddressUpdated(newAddress);
    }

    function setLiquidityFee(uint256 newFee) public onlyOwner {
        checkFeesChanged(liquidityFee, newFee);
        liquidityFee = newFee;
        _updateTotalFee();
        emit LiquidityFeeUpdated(newFee);
    }

    function setBurnFee(uint256 newFee) public onlyOwner {
        checkFeesChanged(burnFee, newFee);
        burnFee = newFee;
        _updateTotalFee();
        emit BurnFeeUpdated(newFee);
    }

    function setAntiDumpThreshold(uint256 newThreshold) public onlyOwner {
        require(newThreshold >= ANTI_DUMP_THRESHOLD_LIMIT, "The company cannot set abusive threshold");
        antiDumpThreshold = newThreshold;
        emit AntiDumpThresholdUpdated(newThreshold);
    }

    function setLockTime(uint timeBetweenTransactions) external onlyOwner {
        _setLockTime(timeBetweenTransactions);
    }

    function _updateTotalFee() internal {
        totalFees = liquidityFee.add(burnFee).add(ecoSystemFee);
    }

    function _swapAndLiquify(uint256 amount, address cakeReceiver) private {
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);  // token

        uint256 initialAmount = address(this).balance;

        _swapTokensForBNB(half);

        uint256 newAmount = address(this).balance.sub(initialAmount);  // bnb

        _addLiquidity(otherHalf, newAmount, cakeReceiver);

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

    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount, address cakeReceiver) private {
        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{ value: bnbAmount }(
            address(this),
            tokenAmount,
            0,
            0,
            cakeReceiver,
            block.timestamp.add(300)
        );
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    modifier _checkIfPairIsAuthorized(address from, address to) {
        // if the contract has symbol and the name is Cake-LP, it is a pancake pair
        if(Address.isContract(from) && !automatedMarketMakerPairs[from]) {
            try IUniswapV2Pair(from).symbol() returns (string memory _value) {
                if(compareStrings(_value, "Cake-LP")) 
                    revert("pair not allowed");
            }
            catch {}
        }
        if(Address.isContract(to) && !automatedMarketMakerPairs[to]) {
            try IUniswapV2Pair(to).symbol() returns (string memory _value) {
                if(compareStrings(_value, "Cake-LP"))
                    revert("pair not allowed");
            }
            catch {}
        }
        _;
    }

    function getTokenVolumeFromPair(address pairAddr) internal view returns (uint256){
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddr).getReserves();

        if(pair.token0() == address(this))
            return reserve0;
        else if(pair.token1() == address(this))
            return reserve1;
        else
            revert("not a pair");
    }

    function timeLockCheck(address from, address to) internal {
        if(automatedMarketMakerPairs[to])  // selling tokens
            lockIfCanOperateAndRevertIfNotAllowed(from);
        else if(automatedMarketMakerPairs[from]) // buying tokens
            lockIfCanOperateAndRevertIfNotAllowed(to);
    }

    function setAntiDump(uint256 newThreshold, uint256 newFee) external onlyOwner {
        require(newThreshold >= ANTI_DUMP_THRESHOLD_LIMIT, "new threshold is not acceptable");
        require(newFee<=ANTI_DUMP_FEE_LIMIT, "new fee is not acceptable");

        antiDumpThreshold = newThreshold;
        antiDumpFee = newFee;

        emit SetAntiDump(newThreshold, newFee);
    }
    event SetAntiDump(uint256 newThreshold, uint256 newfee);

    function antiDumpCheck(address from, address to, uint256 amount) internal view returns(uint256) {
        address pair = DEAD_ADDRESS;

        // we dont need "from" for now, but, we will keep it here for completeness

        // check if the transaction direction is sell token
        if(automatedMarketMakerPairs[to])
            pair = to;
//        else if(automatedMarketMakerPairs[from])
//            pair = from;

        if(pair!=DEAD_ADDRESS) {
            uint256 volume = getTokenVolumeFromPair(pair);
            if (volume > 0) {
                uint256 maxVolume = volume.mul(antiDumpThreshold).div(10**decimals());
                if (amount >= maxVolume)
                    return antiDumpFee;
            }
        }
        return 0;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override
    _checkIfPairIsAuthorized(from, to)
    {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];

        if (excludedAccount) {
            super._transfer(from, to, amount);
        } else {
            // timelock dex transactions
            timeLockCheck(from,to);
            uint256 extraFee = antiDumpCheck(from, to, amount);
            uint256 tokenToEcoSystem=0;
            uint256 tokensToLiquidity=0;
            uint256 tokensToBurn=0;

            // automatedMarketMakerPairs[from] -> buy tokens on dex
            // automatedMarketMakerPairs[to]   -> sell tokens on dex
            if(automatedMarketMakerPairs[to] || automatedMarketMakerPairs[from]) {
                // apply ecoSystemFee if enabled
                if (ecoSystemFee > 0) {
                    tokenToEcoSystem = amount.mul(ecoSystemFee.add(extraFee)).div(10 ** decimals());
                    super._transfer(from, ecoSystemAddress, tokenToEcoSystem);
                }

                // apply liquidity fee
                if (liquidityFee > 0) {
                    tokensToLiquidity = amount.mul(liquidityFee).div(10 ** decimals());
                    super._transfer(from, address(this), tokensToLiquidity);

                    // SELL _swapAndLiquify fails if we add liquidity and from == dexPair. it is a uniswap known issue
                    if(automatedMarketMakerPairs[to]){
                        // Company receives lp token
                        if(liquidityAddress != DEAD_ADDRESS){
                            if (balanceOf(address(this)) >= numTokensSellToAddToLiquidity)
                                _swapAndLiquify(balanceOf(address(this)), liquidityAddress);
                        }
                        // Cashback the user with LP token
                        else
                            _swapAndLiquify(tokensToLiquidity, from);
                    }
                    // The LP token from BUY and will be stored inside the contract until the company withdraws it
                }
            }

            // apply burn fees always
            if (burnFee > 0) {
                tokensToBurn = amount.mul(burnFee).div(10 ** decimals());
                super._transfer(from, DEAD_ADDRESS, tokensToBurn);
            }

            uint256 amountMinusFees = amount.sub(tokenToEcoSystem).sub(tokensToLiquidity).sub(tokensToBurn);
            super._transfer(from, to, amountMinusFees);
        }
    }

    // @dev unlock a wallet for one transaction
    function unlockWallet(address wallet) public onlyOwner {
        _unlockWallet(wallet);
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
    event AntiDumpThresholdUpdated(uint256 indexed threshold);
}