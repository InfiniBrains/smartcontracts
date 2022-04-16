// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./TimeLockTransactions.sol";
import "./WithdrawableOwnable.sol";
import "./AntiDumpOwnable.sol";

contract UltimateERC20 is IERC20, Ownable, TimeLockTransactions, WithdrawableOwnable, AntiDumpOwnable {
    using SafeMath for uint256;
    using Address for address;

    struct FeeTier {
        uint256 ecoSystemFee;
        address ecoSystem;
        uint256 stakingFee;
        address staking; // wallet para dividendos para detentores de HRS
        uint256 liquidityFee; // fee to add funds to the DEX
        uint256 taxFee;
        uint256 burnFee;
    }

    struct FeeValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rFee;
        uint256 tTransferAmount;
        uint256 tEcoSystem;
        uint256 tStaking;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tBurn;
    }

    struct tFeeValues {
        uint256 tTransferAmount;
        uint256 tEcoSystem;
        uint256 tStaking;
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

    // @dev which wallet will receive the ecosystem fee. If dead is used, it goes to the msgSender
    address public liquidityAddress;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;

    uint256 public numTokensSellToAddToLiquidity;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiquidity
    );

    // @dev just a protection
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
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

    // @dev the constructor
    constructor (string memory __name, string memory __symbol) AntiDumpOwnable(9) {
        _name = __name;
        _symbol = __symbol;
        _decimals = 9;

        _tTotal = 1000000000 * 10**_decimals;
        _rTotal = (MAX - (MAX % _tTotal));
        _maxFee = 2 * 10**8; // 20%

        swapAndLiquifyEnabled = false;

        numTokensSellToAddToLiquidity = _tTotal.div(10**6); // 0.000001% of total supply

        _burnAddress = 0x000000000000000000000000000000000000dEaD;
        liquidityAddress = _burnAddress;

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
        // 5*10**6 is 0,5% 5*10**7 is 5%
        _emptyFees = FeeTier({ecoSystemFee:0, stakingFee:0, liquidityFee:5*10**6, taxFee:5*10**6, burnFee:0, ecoSystem:address(this), staking:address(this)});
        _defaultFees = FeeTier({ecoSystemFee:125*10**5, stakingFee:125*10**5, liquidityFee:25*10**6, taxFee:5*10**7, burnFee:0, ecoSystem:address(this), staking:address(this)});
        
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    // @dev create and add a new pair for a given token
    function addNewPair(address tokenAddress) external onlyOwner returns (address np) {
        address newPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this) ,tokenAddress);
        _setAutomatedMarketMakerPair(newPair, true);
        emit AddNewPair(tokenAddress, newPair);
        return newPair;
    }
    event AddNewPair(address indexed tokenAddress, address indexed newPair);

    function setNumTokensSellToAddToLiquidity(uint256 newLimit) external onlyOwner {
        require(newLimit >= totalSupply().div(10**6), "new limit is too low");
        numTokensSellToAddToLiquidity = newLimit;
        emit SetNumTokensSellToAddToLiquidity(newLimit);
    }
    event SetNumTokensSellToAddToLiquidity(uint256 newLimit);

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != defaultPair, "cannot be removed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    // @dev the default name of the contract
    function name() public view returns (string memory) {
        return _name;
    }

    // @dev the symbol of the contract
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    // @dev the numbers of decimals the token have
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

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

    // @dev total fees collected in tax to be used in reflection(i guess)
    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    // todo: is this even useful?
    function reflectionFromTokenInTiers(uint256 tAmount, bool _getDefaultFee, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            FeeValues memory _values = _getValues(tAmount, _getDefaultFee);
            return _values.rAmount;
        } else {
            FeeValues memory _values = _getValues(tAmount, _getDefaultFee);
            return _values.rTransferAmount;
        }
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        return reflectionFromTokenInTiers(tAmount, true, deductTransferFee);
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner() {
        require(!_isExcludedFromReward[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcludedFromReward[account] = true;
        _excluded.push(account);
        emit ExcludeFromReward(account);
    }
    event ExcludeFromReward(address account);

    function includeInReward(address account) public onlyOwner() {
        require(_isExcludedFromReward[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcludedFromReward[account] = false;
                _excluded.pop();
                break;
            }
        }
        emit IncludeInReward(account);
    }
    event IncludeInReward(address account);

    function excludeFromFee(address account) public onlyOwner() {
        _isExcludedFromFee[account] = true;
        emit ExcludeFromFee(account);
    }
    event ExcludeFromFee(address account);

    function includeInFee(address account) public onlyOwner() {
        _isExcludedFromFee[account] = false;
        emit IncludeInFee(account);
    }
    event IncludeInFee(address account);

    function checkFeesChanged(FeeTier memory _tier, uint256 _oldFee, uint256 _newFee) internal view {
        uint256 _fees = _tier.ecoSystemFee
        .add(_tier.stakingFee)
        .add(_tier.liquidityFee)
        .add(_tier.taxFee)
        .add(_tier.burnFee)
        .add(_newFee)
        .sub(_oldFee);

        require(_fees <= _maxFee, "Fees exceeded max limitation");
    }

    function setEcoSystemFeePercent(uint256 _empty, uint256 _default) external onlyOwner() {
        if(_default != _defaultFees.ecoSystemFee) {
            checkFeesChanged(_defaultFees, _defaultFees.ecoSystemFee, _default);
            _defaultFees.ecoSystemFee = _default;
        }

        if(_empty != _emptyFees.ecoSystemFee) {
            checkFeesChanged(_emptyFees, _emptyFees.ecoSystemFee, _empty);
            _emptyFees.ecoSystemFee = _empty;
        }

        emit SetEcoSystemFeePercent(_empty, _default);
    }

    event SetEcoSystemFeePercent(uint256 _empty, uint256 _default);

    function setStakingFeePercent(uint256 _empty, uint256 _default) external onlyOwner() {
        if(_default != _defaultFees.stakingFee) {
            checkFeesChanged(_defaultFees, _defaultFees.stakingFee, _default);
            _defaultFees.stakingFee = _default;
        }

        if(_empty != _emptyFees.stakingFee) {
            checkFeesChanged(_emptyFees, _emptyFees.stakingFee, _empty);
            _emptyFees.stakingFee = _empty;
        }

        emit SetStakingFeePercent(_empty, _default);
    }

    event SetStakingFeePercent(uint256 _empty, uint256 _default);

    function setLiquidityFeePercent(uint256 _empty, uint256 _default) external onlyOwner() {
        if(_default != _defaultFees.liquidityFee) {
            checkFeesChanged(_defaultFees, _defaultFees.liquidityFee, _default);
            _defaultFees.liquidityFee = _default;
        }

        if(_empty != _emptyFees.liquidityFee) {
            checkFeesChanged(_emptyFees, _emptyFees.liquidityFee, _empty);
            _emptyFees.liquidityFee = _empty;
        }

        emit SetLiquidityFeePercent(_empty, _default);
    }

    event SetLiquidityFeePercent(uint256 _empty, uint256 _default);

    function setTaxFeePercent(uint256 _empty, uint256 _default) external onlyOwner() {
        if(_default != _defaultFees.taxFee) {
            checkFeesChanged(_defaultFees, _defaultFees.taxFee, _default);
            _defaultFees.taxFee = _default;
        }

        if(_empty != _emptyFees.taxFee) {
            checkFeesChanged(_emptyFees, _emptyFees.taxFee, _empty);
            _emptyFees.taxFee = _empty;
        }

        emit SetTaxFeePercent(_empty, _default);
    }

    event SetTaxFeePercent(uint256 _empty, uint256 _default);

    function setBurnFeePercent(uint256 _empty, uint256 _default) external onlyOwner() {
        if(_default != _defaultFees.burnFee) {
            checkFeesChanged(_defaultFees, _defaultFees.burnFee, _default);
            _defaultFees.burnFee = _default;
        }

        if(_empty != _emptyFees.burnFee) {
            checkFeesChanged(_emptyFees, _emptyFees.burnFee, _empty);
            _emptyFees.burnFee = _empty;
        }

        emit SetBurnFeePercent(_empty, _default);
    }

    event SetBurnFeePercent(uint256 _empty, uint256 _default);

    function setEcoSystemFeeAddress(address _empty, address _default) external onlyOwner() {
        if(_default != _defaultFees.ecoSystem) {
            require(_default != address(0), "Address Zero is not allowed");
            includeInReward(_defaultFees.ecoSystem);
            _defaultFees.ecoSystem = _default;
            excludeFromReward(_default);
        }
        if(_empty != _emptyFees.ecoSystem) {
            require(_empty != address(0), "Address Zero is not allowed");
            includeInReward(_emptyFees.ecoSystem);
            _emptyFees.ecoSystem = _empty;
            excludeFromReward(_empty);
        }
        emit SetEcoSystemFeeAddress(_empty, _default);
    }

    event SetEcoSystemFeeAddress(address _empty, address _default);

    function setStakingFeeAddress(address _empty, address _default) external onlyOwner() {
        if(_default != _defaultFees.staking) {
            require(_default != address(0), "Address Zero is not allowed");
            includeInReward(_defaultFees.staking);
            _defaultFees.staking = _default;
            excludeFromReward(_default);
        }
        if(_empty != _emptyFees.staking) {
            require(_empty != address(0), "Address Zero is not allowed");
            includeInReward(_emptyFees.staking);
            _emptyFees.staking = _empty;
            excludeFromReward(_empty);
        }
        emit SetStakingFeeAddress(_empty, _default);
    }

    event SetStakingFeeAddress(address _empty, address _default);

    // @dev set liquidity address to receive fees, id dead, the lp token goes to the user
    function setLiqudityFeeAddress(address newAddress) public onlyOwner {
        require(liquidityAddress != newAddress, "Liquidity address already setted");
        require(liquidityAddress != address(0), "Address Zero is not allowed");
        includeInReward(liquidityAddress);
        liquidityAddress = newAddress;
        excludeFromReward(newAddress);
        emit SetLiqudityFeeAddress(newAddress);
    }

    event SetLiqudityFeeAddress(address indexed liquidityAddress);

    function updateRouter(address _uniswapV2Router) public onlyOwner() {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        emit UpdateRouter(_uniswapV2Router);
    }
    event UpdateRouter(address _uniswapV2Router);

    // @dev enable the swap mechanisms. This can only be enabled. The owner cannot disable swap or lock the contract by any means.
    function enableSwapAndLiquify() external onlyOwner() {
        swapAndLiquifyEnabled = true;
        emit SwapAndLiquifyEnabledUpdated(true);
    }

    //to receive BNB from uniswapV2Router when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount, bool _getDefault) private view returns (FeeValues memory) {
        tFeeValues memory tValues = _getTValues(tAmount, _getDefault);
        uint256 tTransferFee = tValues.tLiquidity.add(tValues.tEcoSystem).add(tValues.tStaking).add(tValues.tBurn);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tValues.tFee, tTransferFee, _getRate());
        return FeeValues(rAmount, rTransferAmount, rFee, tValues.tTransferAmount, tValues.tEcoSystem, tValues.tStaking, tValues.tLiquidity, tValues.tFee, tValues.tBurn);
    }

    function _getTValues(uint256 tAmount, bool _getDefault) private view returns (tFeeValues memory) {
        FeeTier memory tier = _getDefault ? _defaultFees : _emptyFees;
        tFeeValues memory tValues = tFeeValues(
            0,
            calculateFee(tAmount, tier.ecoSystemFee),
            calculateFee(tAmount, tier.stakingFee),
            calculateFee(tAmount, tier.liquidityFee),
            calculateFee(tAmount, tier.taxFee),
            calculateFee(tAmount, tier.burnFee)
        );
        tValues.tTransferAmount = tAmount.sub(tValues.tEcoSystem).sub(tValues.tStaking).sub(tValues.tFee).sub(tValues.tLiquidity).sub(tValues.tBurn);
        return tValues;
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tTransferFee, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferFee = tTransferFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rTransferFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function calculateFee(uint256 _amount, uint256 _fee) private pure returns (uint256) {
        if(_fee == 0) return 0;
        return _amount.mul(_fee).div(
            10**9
        );
    }

    function removeAllFee() private {
        _previousFees = _defaultFees;
        _defaultFees = _emptyFees;
    }

    function restoreAllFee() private {
        _defaultFees = _previousFees;
    }

    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    )
    private
    {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function timeLockCheck(address from, address to) internal {
        if(automatedMarketMakerPairs[to])  // selling tokens
            lockIfCanOperateAndRevertIfNotAllowed(from);
        else if(automatedMarketMakerPairs[from]) // buying tokens
            lockIfCanOperateAndRevertIfNotAllowed(to);
    }


    function _transfer(
        address from,
        address to,
        uint256 amount
    )
    private
    _checkIfPairIsAuthorized(from, to)
    {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        bool isDefaultFee = true;

        if(takeFee) {
            if(_msgSender() != from) isDefaultFee = !_isExcludedFromFee[_msgSender()];
            else isDefaultFee = !_isExcludedFromFee[from];
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, isDefaultFee, takeFee);
    }

    function swapAndLiquify(uint256 contractTokenBalance, address cakeReceiver) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current BNB balance.
        // this is so that we can capture exactly the amount of BNB that the
        // swap creates, and not make the liquidity event include any BNB that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for BNB
        swapTokensForBnb(half);

        // how much BNB did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance, cakeReceiver);

        // todo: inspect if some tokens still remains in the contract caused by accumulation of small slippages when addLiquidity

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForBnb(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of BNB
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount, address cakeReceiver) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: bnbAmount }(
            address(this),
            tokenAmount,
            0,
            0,
            cakeReceiver,
            block.timestamp.add(300)
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool _isDefaultFee, bool takeFee) private {
        FeeTier storage _feesWithAntiDump = _defaultFees;
        uint256 _previousTaxFee = _feesWithAntiDump.taxFee;

        if(!takeFee)
            removeAllFee();
        else { // check antidump 
            if(automatedMarketMakerPairs[recipient]) {
                uint256 extraFee = getAntiDumpFee(recipient, amount);
                // add antidump fee to reflection fee
                _feesWithAntiDump.taxFee = _feesWithAntiDump.taxFee.add(extraFee);
            } 
            // check authorized time window
            timeLockCheck(sender, recipient);
        }

        if (_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferFromExcluded(sender, recipient, amount, _isDefaultFee);
        } else if (!_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferToExcluded(sender, recipient, amount, _isDefaultFee);
        } else if (!_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferStandard(sender, recipient, amount, _isDefaultFee);
        } else if (_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferBothExcluded(sender, recipient, amount, _isDefaultFee);
        } else {
            _transferStandard(sender, recipient, amount, _isDefaultFee);
        }

        if(!takeFee)
            restoreAllFee();
        else {
            _feesWithAntiDump.taxFee = _previousTaxFee; // reset tax fee
        }
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount, bool _isDefaultFee) private {
        FeeValues memory _values = _getValues(tAmount, _isDefaultFee);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(sender, _values, _isDefaultFee);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount, bool _isDefaultFee) private {
        FeeValues memory _values = _getValues(tAmount, _isDefaultFee);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(sender, _values, _isDefaultFee);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount, bool _isDefaultFee) private {
        FeeValues memory _values = _getValues(tAmount, _isDefaultFee);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(sender, _values, _isDefaultFee);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount, bool _isDefaultFee) private {
        FeeValues memory _values = _getValues(tAmount, _isDefaultFee);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(sender, _values, _isDefaultFee);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _takeFees(address sender, FeeValues memory values, bool _isDefaultFee) private {
        _takeFee(sender, values.tLiquidity, address(this));

        bool overMinTokenBalance = balanceOf(address(this)) >= numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            !automatedMarketMakerPairs[sender] &&
            swapAndLiquifyEnabled
        ) {
            //add liquidity
            if(liquidityAddress != _burnAddress) swapAndLiquify(balanceOf(address(this)), liquidityAddress);
            else if (values.tLiquidity > 0) swapAndLiquify(values.tLiquidity, sender);
        }

        if(_isDefaultFee) {
            _takeFee(sender, values.tEcoSystem, _defaultFees.ecoSystem);
            _takeFee(sender, values.tStaking, _defaultFees.staking);
        }
        else {
            _takeFee(sender, values.tEcoSystem, _emptyFees.ecoSystem);
            _takeFee(sender, values.tStaking, _emptyFees.staking);
        }
        _takeBurn(sender, values.tBurn);
    }

    function _takeFee(address sender, uint256 tAmount, address recipient) private {
        if(recipient == address(0)) return;
        if(tAmount == 0) return;

        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount.mul(currentRate);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        if(_isExcludedFromReward[recipient])
            _tOwned[recipient] = _tOwned[recipient].add(tAmount);

        emit Transfer(sender, recipient, tAmount);
    }

    function _takeBurn(address sender, uint256 _amount) private {
        if(_amount == 0) return;
        _tOwned[_burnAddress] = _tOwned[_burnAddress].add(_amount);

        emit Transfer(sender, _burnAddress, _amount);
    }

    function updateBurnAddress(address _newBurnAddress) external onlyOwner() {
        _burnAddress = _newBurnAddress;
        excludeFromReward(_newBurnAddress);
    }
}
