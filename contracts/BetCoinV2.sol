// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract BetCoinV2 is IERC20, Context, Ownable {
    using SafeMath for uint256;
    using Address for address;

    struct FeeTier {
        uint256 ecoSystemFee;
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
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tOwner;
        uint256 tBurn;
    }

    struct tFeeValues {
        uint256 tTransferAmount;
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tOwner;
        uint256 tBurn;
    }

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;

    /**
      * @dev whitelist
      */
    mapping (address => bool) private _whitelist; // todo: probably a set works better

    // todo: improve this. we are iterating over this. and this might be costly
    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;
    uint256 private _maxFee;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    FeeTier public _defaultFees;
    FeeTier private _previousFees;
    FeeTier private _emptyFees;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public WBNB;
    address private _initializerAccount;
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

    modifier isRouter(address _sender) {
        {
            uint32 size;
            assembly {
                size := extcodesize(_sender)
            }
            if(size > 0) {
                // todo: test this!
                bool senderTier = _whitelist[_sender];
                if(senderTier == false) {
                    IUniswapV2Router02 _routerCheck = IUniswapV2Router02(_sender);
                    try _routerCheck.factory() returns (address factory) {
                        _whitelist[_sender] = true;
                    } catch {

                    }
                }
            }
        }

        _;
    }


    constructor () public {
        //        _rOwned[_msgSender()] = _rTotal;
        //
        //        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
        //        // Create a uniswap pair for this new token
        //        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
        //        .createPair(address(this), _uniswapV2Router.WETH());
        //
        //        // set the rest of the contract variables
        //        uniswapV2Router = _uniswapV2Router;
        //
        //        //exclude owner and this contract from fee
        //        _isExcludedFromFee[owner()] = true;
        //        _isExcludedFromFee[address(this)] = true;
        //
        //        __BetCoin_v2_init_unchained(_router);
        //
        //        emit Transfer(address(0), _msgSender(), _tTotal);

        __BetCoin_v2_init_unchained(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    }

    //    function initialize(address _router) public initializer {
    //        __Context_init_unchained();
    //        __Ownable_init_unchained();
    //        __BetCoin_v2_init_unchained(_router);
    //    }

    function __BetCoin_v2_init_unchained(address _router) internal {
        _name = "MatchBet Coin";
        _symbol = "MTC";
        _decimals = 18;

        _tTotal = 1000000 * 10**6 * _decimals;
        _rTotal = (MAX - (MAX % _tTotal));
        _maxFee = 1000;

        swapAndLiquifyEnabled = true;

        _maxTxAmount = 5000 * 10**6 * _decimals;
        numTokensSellToAddToLiquidity = 500 * 10**6 * _decimals;

        _burnAddress = 0x000000000000000000000000000000000000dEaD;
        _initializerAccount = _msgSender();

        _rOwned[_initializerAccount] = _rTotal;

        uniswapV2Router = IUniswapV2Router02(_router);
        WBNB = uniswapV2Router.WETH();

        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
        .createPair(address(this), WBNB);

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        __BetCoin_tiers_init();

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function __BetCoin_tiers_init() internal {
        _defaultFees = FeeTier({ecoSystemFee:0, liquidityFee:500, taxFee:500, ownerFee:0, burnFee:0, ecoSystem:address(0), owner:address(0)});
        _emptyFees = FeeTier({ecoSystemFee:50, liquidityFee:5000, taxFee:5000, ownerFee:0, burnFee:0, ecoSystem:address(0), owner:address(0)});
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

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
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
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

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
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) public onlyOwner() {
        require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFee(address account) public onlyOwner() {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner() {
        _isExcludedFromFee[account] = false;
    }

    function whitelistAddress(address _account) public onlyOwner()
    {
        require(_account != address(0), "BetCoin: Invalid address");
        _whitelist[_account] = true;
    }

    function excludeWhitelistedAddress(address _account) public onlyOwner() {
        require(_account != address(0), "BetCoin: Invalid address");
        require(_whitelist[_account] == true, "BetCoin: Account is not in whitelist");
        delete _whitelist[_account];
    }

    event ExcludeWhitelistedAddress(address _account);

    function isWhitelisted(address _account) public view returns (bool) {
        return _whitelist[_account];
    }

    function checkFees(FeeTier memory _tier) internal view returns (FeeTier memory) {
        uint256 _fees = _tier.ecoSystemFee.add(_tier.liquidityFee).add(_tier.taxFee).add(_tier.ownerFee).add(_tier.burnFee);
        require(_fees <= _maxFee, "BetCoin: Fees exceeded max limitation");

        return _tier;
    }

    function checkFeesChanged(FeeTier memory _tier, uint256 _oldFee, uint256 _newFee) internal view {
        uint256 _fees = _tier.ecoSystemFee
        .add(_tier.liquidityFee)
        .add(_tier.taxFee)
        .add(_tier.ownerFee)
        .add(_tier.burnFee)
        .sub(_oldFee)
        .add(_newFee);

        require(_fees <= _maxFee, "BetCoin: Fees exceeded max limitation");
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

    function setOwnerFeePercent(uint256 _empty, uint256 _default) external onlyOwner() {
        if(_default != _defaultFees.ownerFee) {
            checkFeesChanged(_defaultFees, _defaultFees.ownerFee, _default);
            _defaultFees.ownerFee = _default;
        }

        if(_empty != _emptyFees.ownerFee) {
            checkFeesChanged(_emptyFees, _emptyFees.ownerFee, _empty);
            _emptyFees.ownerFee = _empty;
        }

        emit SetOwnerFeePercent(_empty, _default);
    }

    event SetOwnerFeePercent(uint256 _empty, uint256 _default);

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
            require(_default != address(0), "BetCoin: Address Zero is not allowed");
            includeInReward(_defaultFees.ecoSystem);
            _defaultFees.ecoSystem = _default;
            excludeFromReward(_default);
        }
        if(_empty != _emptyFees.ecoSystem) {
            require(_empty != address(0), "BetCoin: Address Zero is not allowed");
            includeInReward(_emptyFees.ecoSystem);
            _emptyFees.ecoSystem = _empty;
            excludeFromReward(_empty);
        }
        emit SetEcoSystemFeeAddress(_empty, _default);
    }

    event SetEcoSystemFeeAddress(address _empty, address _default);

    function setOwnerFeeAddress(address _empty, address _default) external onlyOwner() {
        if(_default != _defaultFees.owner) {
            require(_default != address(0), "BetCoin: Address Zero is not allowed");
            includeInReward(_defaultFees.owner);
            _defaultFees.owner = _default;
            excludeFromReward(_default);
        }
        if(_empty != _emptyFees.owner) {
            require(_empty != address(0), "BetCoin: Address Zero is not allowed");
            includeInReward(_emptyFees.owner);
            _emptyFees.owner = _empty;
            excludeFromReward(_empty);
        }
        emit SetOwnerFeeAddress(_empty, _default);
    }

    event SetOwnerFeeAddress(address _empty, address _default);

    function updateRouterAndPair(address _uniswapV2Router,address _uniswapV2Pair) public onlyOwner() {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV2Pair = _uniswapV2Pair;
        WBNB = uniswapV2Router.WETH();
    }

    function setDefaultSettings() external onlyOwner() {
        swapAndLiquifyEnabled = true;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(
            10**4
        );
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner() {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    //to receive BNB from uniswapV2Router when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount, bool _getDefault) private view returns (FeeValues memory) {
        tFeeValues memory tValues = _getTValues(tAmount, _getDefault);
        uint256 tTransferFee = tValues.tLiquidity.add(tValues.tEchoSystem).add(tValues.tOwner).add(tValues.tBurn);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tValues.tFee, tTransferFee, _getRate());
        return FeeValues(rAmount, rTransferAmount, rFee, tValues.tTransferAmount, tValues.tEchoSystem, tValues.tLiquidity, tValues.tFee, tValues.tOwner, tValues.tBurn);
    }

    function _getTValues(uint256 tAmount, bool _getDefault) private view returns (tFeeValues memory) {
        FeeTier memory tier = _getDefault ? _defaultFees : _emptyFees;
        tFeeValues memory tValues = tFeeValues(
            0,
            calculateFee(tAmount, tier.ecoSystemFee),
            calculateFee(tAmount, tier.liquidityFee),
            calculateFee(tAmount, tier.taxFee),
            calculateFee(tAmount, tier.ownerFee),
            calculateFee(tAmount, tier.burnFee)
        );

        tValues.tTransferAmount = tAmount.sub(tValues.tEchoSystem).sub(tValues.tFee).sub(tValues.tLiquidity).sub(tValues.tOwner).sub(tValues.tBurn);
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
            10**4
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

    function _transfer(
        address from,
        address to,
        uint256 amount
    )
    private
//    preventBlacklisted(_msgSender(), "BetCoin: Address is blacklisted")
//    preventBlacklisted(from, "BetCoin: From address is blacklisted")
//    preventBlacklisted(to, "BetCoin: To address is blacklisted")
    isRouter(_msgSender())
    {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if(from != owner() && to != owner())
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        if(contractTokenBalance >= _maxTxAmount)
        {
            contractTokenBalance = _maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        bool isDefaultFee = true;

        if(takeFee) {
            isDefaultFee = !_whitelist[from]; // todo: test this

            if(_msgSender() != from) {
                isDefaultFee = !_whitelist[_msgSender()];
            }
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, isDefaultFee, takeFee);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
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
        addLiquidity(otherHalf, newBalance);

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

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool _isDefaultFee, bool takeFee) private {
        if(!takeFee)
            removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount, _isDefaultFee);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount, _isDefaultFee);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount, _isDefaultFee);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount, _isDefaultFee);
        } else {
            _transferStandard(sender, recipient, amount, _isDefaultFee);
        }

        if(!takeFee)
            restoreAllFee();
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
        if(_isDefaultFee) {
            _takeFee(sender, values.tEchoSystem, _defaultFees.ecoSystem);
            _takeFee(sender, values.tOwner, _defaultFees.owner);
        }
        else {
            _takeFee(sender, values.tEchoSystem, _emptyFees.ecoSystem);
            _takeFee(sender, values.tOwner, _emptyFees.owner);
        }
        _takeBurn(sender, values.tBurn);
    }

    function _takeFee(address sender, uint256 tAmount, address recipient) private {
        if(recipient == address(0)) return;
        if(tAmount == 0) return;

        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount.mul(currentRate);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        if(_isExcluded[recipient])
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

    function withdraw() onlyOwner public {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    /**
     * @dev Withdraw any ERC20 token from this contract
     * @param tokenAddress ERC20 token to withdraw
     * @param to receiver address
     * @param amount amount to withdraw
     */
    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyOwner {
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }
}
