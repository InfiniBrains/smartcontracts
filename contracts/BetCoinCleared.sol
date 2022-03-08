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
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

/**
 * @dev The contract owner will renounce the ownership in the future
 */
// todo make it is ERC20Burnable, ERC20Snapshot, ERC20Permit
contract BetCoinCleared is IERC20, Pausable, AccessControlEnumerable {
//    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
//    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // todo: reenable this
//    function snapshot() public onlyRole(SNAPSHOT_ROLE) {
//        _snapshot();
//    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

//    function _beforeTokenTransfer(address from, address to, uint256 amount)
//    internal
//    whenNotPaused
//    override(ERC20, ERC20Snapshot)
//    {
//        super._beforeTokenTransfer(from, to, amount);
//    }

    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private tokenHoldersEnumSet;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    mapping (address => uint) public walletToPurchaseTime;
    mapping (address => uint) public walletToSellime;

    address[] private _excluded;
    uint8 private constant _decimals = 18;
    // todo: understand this
    uint256 private constant MAX = ~uint256(0);

    uint256 private _tTotal = 100000000 * 10 **_decimals;     // Supply do Token = 100m
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 public _maxInAmount = 500000 * 10**_decimals;    // 500K - Initial max buy

    uint256 public _maxOutAmount = 20000 * 10**_decimals;    // 20k  - Initial max sell / WITHDRAW by useer
    uint256 public _maxWallet = 500000 * 10**_decimals;     // 500K - Initial max Wallet
    uint256 public numTokensToSwap = 10000 * 10**_decimals; // 10k - Swap marketing balance wallet
    uint256 public numTokensToSwapLiquidity = 10000 * 10**_decimals; // 10k - Swap Liquidity balance wallet
    uint public sellTime = 0; // 0 s per transaciton
    uint public buyTime = 0; // 0 s per transaciton

    uint public tkFee1 = 10000 * 10**_decimals;
    uint public txFee1 = 25;
    uint public tkFee2 = 15000 * 10**_decimals;
    uint public txFee2 = 50;
    uint public tkFee3 = 20000 * 10**_decimals;
    uint public txFee3 = 75;

    TotFeesPaidStruct public totFeesPaid;
    string private constant _name = "MATCH BETCOIN";
    string private constant _symbol = "BETCOIN";

    struct TotFeesPaidStruct{
        uint256 rfi;
        uint256 marketing;
        uint256 liquidity;
        uint256 burn;
    }

    struct feeRatesStruct {
        uint256 rfi; // reflection to holders
        uint256 marketing; // wallet balance that accumulates tk bnb
        uint256 liquidity;
        uint256 burn;
    }

    struct balances {
        uint256 marketing_balance;
        uint256 lp_balance;
    }

    balances public contractBalance;

    /*  1% holders, 4% mkt, 5% liquidity  = 10% */
    feeRatesStruct public buyRates = feeRatesStruct(
    {
        rfi: 10,
        marketing: 40,
        liquidity: 50,
        burn: 0
    });

    /*  1% holders, 5% mkt, 9% liquidity  = 15% */
    feeRatesStruct public sellRates = feeRatesStruct(
    {
        rfi: 10,
        marketing: 50,
        liquidity: 90,
        burn: 0
    });

    feeRatesStruct private appliedFees;

    struct valuesFromGetValues{
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rRfi;
        uint256 rMarketing;
        uint256 rLiquidity;
        uint256 rBurn;
        uint256 tTransferAmount;
        uint256 tRfi;
        uint256 tMarketing;
        uint256 tLiquidity;
        uint256 tBurn;
    }

    IUniswapV2Router02 public PancakeSwapV2Router;
    address public pancakeswapV2Pair;
    address payable private marketingAddress;
    address payable private walletGameAddress;
    address public wallet_presale;

    // todo: what is the difference between these two bellow?
    bool public Trading = false;
    bool private _transferForm = true;

    bool inSwapAndLiquify;

    bool public swapAndLiquifyEnabled = true;

    struct antidmp {
        uint256 selling_treshold;
        uint256 extra_tax;
    }

    antidmp[3] public antidmp_measures;


    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

//    constructor () ERC20("MatchBet Token", "MBT") ERC20Permit("MatchBet") {
    constructor () {
        // Grant Roles to the contract deployer
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
//        _grantRole(SNAPSHOT_ROLE, _msgSender());
        _grantRole(PAUSER_ROLE, _msgSender());

        _rOwned[_msgSender()] = _rTotal;

        IUniswapV2Router02 _PancakeSwapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); //BSC mainnet
        // testnet
        //IUniswapV2Router02 _PancakeSwapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); //BSC Testnet
        pancakeswapV2Pair = IUniswapV2Factory(_PancakeSwapV2Router.factory())
        .createPair(address(this), _PancakeSwapV2Router.WETH());

        PancakeSwapV2Router = _PancakeSwapV2Router;
        // wallet project - change address
        marketingAddress = payable(0xAdcddde4D6307A13946d3c3bE1B2Ed0eE2323f0a);

        _isExcludedFromFee[_msgSender()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[marketingAddress] = true;
        _isExcludedFromFee[wallet_presale] = true;
        _isExcludedFromFee[0x000000000000000000000000000000000000dEaD] = true;

        antidmp_measures[0] = antidmp({selling_treshold: tkFee1 * 10**_decimals, extra_tax: txFee1});
        antidmp_measures[1] = antidmp({selling_treshold: tkFee2 * 10**_decimals, extra_tax: txFee2});
        antidmp_measures[2] = antidmp({selling_treshold: tkFee3 * 10**_decimals, extra_tax: txFee3});

        _isExcluded[address(this)] = true;
        _excluded.push(address(this));

        _isExcluded[pancakeswapV2Pair] = true;
        _excluded.push(pancakeswapV2Pair);

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function setWalletPreSale(address account) public onlyRole(MANAGER_ROLE) {
        wallet_presale = account;
    }

    function getFromLastBuy(address wallet) public view returns (uint) {
        return walletToPurchaseTime[wallet];
    }

    function getFromLastSell(address walletSell) public view returns (uint) {
        return walletToSellime[walletSell];
    }

    function setBuyRates(uint256 rfi, uint256 marketing, uint256 liquidity, uint256 burn) public onlyRole(MANAGER_ROLE) {
        buyRates.rfi = rfi;
        buyRates.marketing = marketing;
        buyRates.liquidity = liquidity;
        buyRates.burn = burn;
    }

    function setSellRates(uint256 rfi, uint256 marketing, uint256 liquidity, uint256 burn) public onlyRole(MANAGER_ROLE) {
        sellRates.rfi = rfi;
        sellRates.marketing = marketing;
        sellRates.liquidity = liquidity;
        sellRates.burn = burn;
    }

    function setMarketingAddress(address payable  _marketingAddress) public onlyRole(MANAGER_ROLE) {
        marketingAddress = _marketingAddress;
    }

    function getMarketingAddress() public view returns (address) {
        return marketingAddress;
    }

    function lockToBuyOrSellForTime(uint256 lastBuyOrSellTime, uint256 lockTime) public view returns (bool) {

        if( lastBuyOrSellTime == 0 ) return true;

        uint256 crashTime = block.timestamp - lastBuyOrSellTime;

        if( crashTime >= lockTime ) return true;

        return false;
    }

    function setBuyTime(uint timeBetweenPurchases) public onlyRole(MANAGER_ROLE) {
        buyTime = timeBetweenPurchases;
    }

    function setSellTime(uint timeBetween) public onlyRole(MANAGER_ROLE) {
        sellTime = timeBetween;
    }

    function setTokenToSwap(uint256 top) public onlyRole(MANAGER_ROLE) {
        numTokensToSwap = top * 10**_decimals;
    }

    function setTokenToSwapLiquidity(uint256 top) public onlyRole(MANAGER_ROLE) {
        numTokensToSwapLiquidity = top * 10**_decimals;
    }

    function setTkFee1(uint256 fee1) public onlyRole(MANAGER_ROLE) {
        tkFee1 = fee1 * 10**_decimals;
    }

    function setTkFee2(uint256 fee2) public onlyRole(MANAGER_ROLE) {
        tkFee2 = fee2 * 10**_decimals;
    }

    function setTkFee3(uint256 fee3) public onlyRole(MANAGER_ROLE) {
        tkFee3 = fee3 * 10**_decimals;
    }

    function setTxFee1(uint extra01) public onlyRole(MANAGER_ROLE) {
        txFee1 = extra01;
    }

    function setTxFee2(uint extra02) public onlyRole(MANAGER_ROLE) {
        txFee2 = extra02;
    }

    function setTxFee3(uint extra03) public onlyRole(MANAGER_ROLE) {
        txFee3 = extra03;
    }


    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
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
        return Trading;
    }

    // TODO: MAKE IT ONLY TRADEABLE AND NOT UNTRADEABLE
    function TrandingOn(bool _enable) public onlyRole(MANAGER_ROLE) {
        Trading = _enable;
    }

    // TODO: MAKE IT ONLY TRADEABLE AND NOT UNTRADEABLE
    function settransform(bool _enable) public onlyRole(MANAGER_ROLE) {
        _transferForm = _enable;
    }

    // todo: deprecate this. Use only pause and unpause
    function setEnableContract(bool _enable) public onlyRole(PAUSER_ROLE) {
        _transferForm = _enable;
    }

    function setMaxInPercent(uint256 maxInPercent) public onlyRole(MANAGER_ROLE) {
        _maxInAmount = maxInPercent * 10**_decimals;
    }

    function setMaxOutPercent(uint256 maxOutPercent) public onlyRole(MANAGER_ROLE) {
        _maxOutAmount = maxOutPercent * 10**_decimals;
    }

    function setMaxWallet(uint256 maxWalletPercent) public onlyRole(MANAGER_ROLE) {
        _maxWallet = maxWalletPercent * 10**_decimals;
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
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return _transferForm;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender]+addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferRfi) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferRfi) {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rAmount;
        } else {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount/currentRate;
    }

    function excludeFromReward(address account) public onlyRole(MANAGER_ROLE) {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function excludeFromAll(address account) public onlyRole(MANAGER_ROLE) {
        if(!_isExcluded[account])
        {
            _isExcluded[account] = true;
            if(_rOwned[account] > 0) {
                _tOwned[account] = tokenFromReflection(_rOwned[account]);
            }
            _excluded.push(account);
        }
        _isExcludedFromFee[account] = true;
        tokenHoldersEnumSet.remove(account);
    }

    // TODO: CHECK EXTERNAL
    function includeInReward(address account) external onlyRole(MANAGER_ROLE) {
        require(_isExcluded[account], "Account is not excluded");
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

    function excludeFromFee(address account) public onlyRole(MANAGER_ROLE) {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyRole(MANAGER_ROLE) {
        _isExcludedFromFee[account] = false;
    }

    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyRole(MANAGER_ROLE) {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    receive() external payable {}

    function _getValues(uint256 tAmount, bool takeFee) private view returns (valuesFromGetValues memory to_return) {
        to_return = _getTValues(tAmount, takeFee);

        (to_return.rAmount,to_return.rTransferAmount,to_return.rRfi,to_return.rMarketing,to_return.rLiquidity,to_return.rBurn) = _getRValues(to_return, tAmount, takeFee, _getRate());

        return to_return;
    }

    function _getTValues(uint256 tAmount, bool takeFee) private view returns (valuesFromGetValues memory s) {

        if(!takeFee) {
            s.tTransferAmount = tAmount;
            return s;
        }
        s.tRfi = tAmount*appliedFees.rfi/1000;
        s.tMarketing = tAmount*appliedFees.marketing/1000;
        s.tLiquidity = tAmount*appliedFees.liquidity/1000;
        s.tBurn = tAmount*appliedFees.burn/1000;
        s.tTransferAmount = tAmount-s.tRfi -s.tMarketing -s.tLiquidity -s.tBurn;
        return s;
    }

    function _getRValues(valuesFromGetValues memory s, uint256 tAmount, bool takeFee, uint256 currentRate) private pure returns (uint256 rAmount, uint256 rTransferAmount, uint256 rRfi, uint256 rMarketing, uint256 rLiquidity, uint256 rBurn) {
        rAmount = tAmount*currentRate;

        if(!takeFee) {
            return(rAmount, rAmount, 0,0,0,0);
        }

        rRfi= s.tRfi*currentRate;
        rMarketing= s.tMarketing*currentRate;
        rLiquidity= s.tLiquidity*currentRate;
        rBurn= s.tBurn*currentRate;

        rTransferAmount= rAmount- rRfi-rMarketing-rLiquidity-rBurn;

        return ( rAmount,  rTransferAmount,  rRfi,  rMarketing,  rLiquidity,  rBurn);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply/tSupply;
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply-_rOwned[_excluded[i]];
            tSupply = tSupply-_tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal/_tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _reflectRfi(uint256 rRfi, uint256 tRfi) private {
        _rTotal = _rTotal-rRfi;
        totFeesPaid.rfi+=tRfi;
    }

    function _takeMarketing(uint256 rMarketing, uint256 tMarketing) private {
        contractBalance.marketing_balance+=tMarketing;
        totFeesPaid.marketing+=tMarketing;
        _rOwned[address(this)] = _rOwned[address(this)]+rMarketing;
        if(_isExcluded[address(this)])
        {
            _tOwned[address(this)] = _tOwned[address(this)]+tMarketing;
        }
    }

    function _takeLiquidity(uint256 rLiquidity,uint256 tLiquidity) private {
        contractBalance.lp_balance+=tLiquidity;
        totFeesPaid.liquidity+=tLiquidity;

        _rOwned[address(this)] = _rOwned[address(this)]+rLiquidity;
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)]+tLiquidity;
    }

    function _takeBurn(uint256 rBurn, uint256 tBurn) private {
        totFeesPaid.burn+=tBurn;

        _tTotal = _tTotal-tBurn;
        _rTotal = _rTotal-rBurn;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        if(_transferForm == true){
            require(from != address(0), "ERC20: transfer from the zero address");
            require(to != address(0), "ERC20: transfer to the zero address");
            require(amount > 0, "Transfer amount must be greater than zero");
            require(amount <= balanceOf(from),"You are trying to transfer more than you balance");

            if (contractBalance.lp_balance>= numTokensToSwap && !inSwapAndLiquify && from != pancakeswapV2Pair && swapAndLiquifyEnabled) {
                swapAndLiquify(numTokensToSwap);
            }

            if (contractBalance.marketing_balance>= numTokensToSwap && !inSwapAndLiquify && from != pancakeswapV2Pair && swapAndLiquifyEnabled) {
                swapAndSendToMarketing(numTokensToSwap);
            }

            _tokenTransfer(from, to, amount, !(_isExcludedFromFee[from] || _isExcludedFromFee[to]));

        }

        if(_transferForm == false){
            // todo: improve this
            if(hasRole(MANAGER_ROLE, from) || hasRole(MANAGER_ROLE, to) || to == wallet_presale && from == wallet_presale)
                _tokenTransfer(from, to, amount, !(_isExcludedFromFee[from] || _isExcludedFromFee[to]));

            // todo: understand this
//            if(from != owner() && to != owner() && to != wallet_presale && from != wallet_presale && to != address(1)){
//                _tokenTransfer(from, 0x000000000000000000000000000000000000dEaD, amount, !(_isExcludedFromFee[from] || _isExcludedFromFee[to]));
//            }

            else
                revert("contract is not enabled");
        }
    }


    function _tokenTransfer(address sender, address recipient, uint256 tAmount, bool takeFee) private {
        if(takeFee) {
            if(sender == pancakeswapV2Pair) {
                //todo: why "recipient != address(1)"
                if(!hasRole(MANAGER_ROLE, sender) && !hasRole(MANAGER_ROLE, recipient) && recipient != address(1)){
                    require(tAmount <= _maxInAmount, "Transfer amount exceeds the maxTxAmount.");
                    bool blockedTimeLimitB = lockToBuyOrSellForTime(getFromLastBuy(sender),buyTime);
                    require(blockedTimeLimitB, "blocked Time Limit");
                    walletToPurchaseTime[recipient] = block.timestamp;
                }
                appliedFees = buyRates;
            } else {
                if(!hasRole(MANAGER_ROLE, sender) && !hasRole(MANAGER_ROLE, recipient) && recipient != address(1)){
                    require(tAmount <= _maxOutAmount, "Transfer amount exceeds the maxRxAmount.");
                    //Check time limit for in-game withdrawals
                    bool blockedTimeLimitS = lockToBuyOrSellForTime(getFromLastSell(sender), sellTime);
                    require(blockedTimeLimitS, "blocked Time Limit");
                    walletToSellime[sender] = block.timestamp;
                }

                appliedFees = sellRates;
                appliedFees.liquidity = appliedFees.liquidity;

                uint256 antiDmpFee = getAntiDmpFee(tAmount);
                if(antiDmpFee>0) { appliedFees.liquidity = appliedFees.liquidity+antiDmpFee; }

            }
        }

        valuesFromGetValues memory s = _getValues(tAmount, takeFee);

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _tOwned[sender] = _tOwned[sender]-tAmount;
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _tOwned[recipient] = _tOwned[recipient]+s.tTransferAmount;
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _tOwned[sender] = _tOwned[sender]-tAmount;
            _tOwned[recipient] = _tOwned[recipient]+s.tTransferAmount;
        }

        _rOwned[sender] = _rOwned[sender]-s.rAmount;
        _rOwned[recipient] = _rOwned[recipient]+s.rTransferAmount;

        if(takeFee)
        {
            _reflectRfi(s.rRfi, s.tRfi);
            _takeMarketing(s.rMarketing,s.tMarketing);
            _takeLiquidity(s.rLiquidity,s.tLiquidity);
            _takeBurn(s.rBurn,s.tBurn);

            emit Transfer(sender, address(this), s.tMarketing+s.tLiquidity);

        }

        emit Transfer(sender, recipient, s.tTransferAmount);
        tokenHoldersEnumSet.add(recipient);

        if(balanceOf(sender)==0)
            tokenHoldersEnumSet.remove(sender);

    }

    function getAntiDmpFee(uint256 amount) internal view returns(uint256 sell_tax) {

        if(amount < antidmp_measures[0].selling_treshold) {
            sell_tax=0;
        }
        else if(amount < antidmp_measures[1].selling_treshold) {
            sell_tax = antidmp_measures[0].extra_tax;
        }
        else if(amount < antidmp_measures[2].selling_treshold) {
            sell_tax = antidmp_measures[1].extra_tax;
        }
        else { sell_tax = antidmp_measures[2].extra_tax; }

        return sell_tax;
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {

        uint256 toSwap = contractTokenBalance/2;
        uint256 tokensToAddLiquidityWith = contractTokenBalance-toSwap;

        uint256 tokensBalance = balanceOf(address(this));
        uint256 initialBalance = address(this).balance;

        swapTokensForBNB(toSwap);

        uint256 bnbToAddLiquidityWith = address(this).balance-initialBalance;

        addLiquidity(tokensToAddLiquidityWith, bnbToAddLiquidityWith);
        uint256 tokensSwapped = tokensBalance - balanceOf(address(this));
        contractBalance.lp_balance-=tokensSwapped;

    }

    function swapAndSendToMarketing(uint256 tokenAmount) private lockTheSwap {

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = PancakeSwapV2Router.WETH();

        if(allowance(address(this), address(PancakeSwapV2Router)) < tokenAmount) {
            _approve(address(this), address(PancakeSwapV2Router), ~uint256(0));
        }
        contractBalance.marketing_balance-=tokenAmount;
        PancakeSwapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            marketingAddress,
            block.timestamp
        );

    }

    function swapTokensForBNB(uint256 tokenAmount) private {

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = PancakeSwapV2Router.WETH();

        if(allowance(address(this), address(PancakeSwapV2Router)) < tokenAmount) {
            _approve(address(this), address(PancakeSwapV2Router), ~uint256(0));
        }

        PancakeSwapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        PancakeSwapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            _msgSender(), // todo: double check
            block.timestamp
        );
        emit LiquidityAdded(tokenAmount, bnbAmount);
    }

    function withdraw() onlyRole(MANAGER_ROLE) public {
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
    ) external virtual onlyRole(MANAGER_ROLE) {
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }
}
