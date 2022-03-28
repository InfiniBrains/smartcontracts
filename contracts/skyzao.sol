//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "hardhat/console.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/safeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./TimeLockDexTransactions.sol";

contract Skyzao is OwnableUpgradeable, ERC20, ERC20Burnable, TimeLockDexTransactions {
    using SafeMath for uint256;
    using Address for address;

    struct FeeTier {
        uint256 liquidityFee;
        uint256 taxFee;
        uint256 ownerFee;
        uint256 burnFee;
        address ecoSystem;
        address owner;
    }

    struct FeeValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rFee;
        uint256 tTransferAmount;
        uint256 tEcoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tBurn;
    }

    struct tFeeValues {
        uint256 tTransferAmount;
        uint256 tEcoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tBurn;
    }

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcludedFromReward;

    // todo: improve this. we are iterating over this. and this might be costly
    address[] private _excluded;

    uint256 private constant MAX = type(uint256).max;
    uint256 private _tTotal;
    uint256 private _rTotal;
    // @dev total reflect fee collected
    uint256 private _tFeeTotal;
    uint256 private _maxFee;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    FeeTier public _defaultFees;
    FeeTier private _previousFees;
    FeeTier private _emptyFees;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapFactoryAddress;
    mapping(address => bool) public automatedMarketMakerPairs;
    address public defaultPair;

    address public _burnAddress;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;

    uint256 public _maxTxAmount;
    uint256 private numTokensSellToAddToLiquidity;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiquidity
    );

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor (string memory __name, string memory __symbol) {
        _name = __name;
        _symbol = __symbol;
        _decimals = 9;

        _tTotal = 1000000000 * 10**_decimals;
        _rTotal = (MAX - (MAX % _tTotal));
        _maxFee = 1000; // 10%

        swapAndLiquifyEnabled = false;

        _maxTxAmount = 5000 * 10**_decimals;
        numTokensSellToAddToLiquidity = 50 * 10**_decimals;

        _burnAddress = 0x000000000000000000000000000000000000dEaD;

        _rOwned[_msgSender()] = _rTotal;

        uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // bsc mainnet router
        uniswapFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73; // pancakeswap factory address

        // Create a uniswap pair for this new token
        defaultPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        _setAutomatedMarketMakerPair(defaultPair, true);

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_burnAddress] = true;
        emit ExcludeFromFee(owner());
        emit ExcludeFromFee(address(this));
        emit ExcludeFromFee(_burnAddress);

//        // todo: check if this is really necessary
//        _isExcludedFromReward[owner()] = true;
        _isExcludedFromReward[address(this)] = true;
        _isExcludedFromReward[_burnAddress] = true;

        // set fees
        // 50 is 0,5% 500 is 5%
        _emptyFees = FeeTier({ecoSystemFee:0, stakingFee:0, liquidityFee:50, taxFee:50, burnFee:0, ecoSystem:address(this), staking:address(this)});
        _defaultFees = FeeTier({ecoSystemFee:125, stakingFee:125, liquidityFee:250, taxFee:500, burnFee:0, ecoSystem:address(this), staking:address(this)});
        
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function addNewPair(address tokenAddress) external onlyOwner returns (address np) {
        address newPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this) ,tokenAddress);
        _setAutomatedMarketMakerPair(newPair, true);
        emit AddNewPair(tokenAddress, newPair);
        return newPair;
    }
    event AddNewPair(address indexed tokenAddress, address indexed newPair);


    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != defaultPair, "cannot be removed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcludedFromReward[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcludedFromReward[account];
    }

    function enableSwapAndLiquify() external onlyOwner() {
        swapAndLiquifyEnabled = true;
        emit SwapAndLiquifyEnabledUpdated(true);
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**4);
    }

    receive() external payable {}

}