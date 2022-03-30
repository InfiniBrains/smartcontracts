// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./TimeLockDexTransactions.sol";

/**
* Features:
*   Fee de liquidez pode ir para todos ou o user ou a empresa(configurável pela empresa)
*   Fee de ecossistema da empresa(configurável pela empresa)
*   Fee de burn. (configurável pela empresa até certo limite)
*   Fees totais limitados a 10%
*   Upgradeable para próximo token
*   Anti whale fees baseado em volume da dex. Configurável até certo limite pela empresa.
*   Time lock dex transactions
*   Impedir que as pessoas criem pares sem autorizacao da empresa.
*/
contract ERC20FLiqFEcoFBurnAntiDumpDexTempBan is ERC20, ERC20Burnable, Pausable, Ownable, TimeLockDexTransactions {
    using SafeMath for uint256;
    using Address for address;

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

    // @dev the total max value of the fee
    uint256 public constant _maxFee = 10 ** 17; // 10%

    // @dev the total supply value of the contract
    uint256 public totalSupplyAtt;

    // @dev the BUSD address
    address public constant _BUSD = address(0x4Fabb145d64652a948d72533023f6E7A623C7C53);

    // @dev the defauld dex router
    IUniswapV2Router02 public dexRouter;

    // @dev the dex factory address
    address public uniswapFactoryAddress;

    // @dev just to simplify to the user, the total fees
    uint256 public totalFees = 0;

    // @dev antidump mechanics
    uint256 public maxTransferFee;

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
        maxTransferFee = 1 ether;

        totalSupplyAtt = totalSupply;

        _mint(owner(), totalSupply);
        
        dexRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // bsc mainnet router
        uniswapFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73; // pancakeswap factory address

        // Create a uniswap pair for this new token
//        dexPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), dexRouter.WETH());
        dexPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), _BUSD); // busd address
        _setAutomatedMarketMakerPair(dexPair, true);

        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[DEAD_ADDRESS] = true;
        emit ExcludeFromFees(owner(), true);
        emit ExcludeFromFees(address(this), true);
        emit ExcludeFromFees(DEAD_ADDRESS, true);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != dexPair, "cannot be removed");
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
        require(_fees <= _maxFee, "Fees exceeded max limitation");
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

    function setLockTime(uint timeBetweenTransactions) external onlyOwner {
        _setLockTime(timeBetweenTransactions);
    }

    // todo: fix: company shouldnt have the ability to set maxTransferFee to zero and block all transactions
    function setMaxTransferFee(uint mtf) external onlyOwner {
        require(mtf > 0, "Can't to set maxTransferFee to zero");
        maxTransferFee = mtf;
    }

    function _updateTotalFee() internal {
        totalFees = liquidityFee.add(burnFee).add(ecoSystemFee);
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
        path[1] = _BUSD; // TODO: test if this is something viable. the oldest value was "path[1] = dexRouter.WETH();"

        _approve(address(this), address(dexRouter), tokenAmount);

        // todo: change this to swapExactTokensForTokensSupportingFeeOnTransferTokens bc we are using busd as 2nd element of the pair
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

        // TODO: make it work with BUSD use addLiquidity https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02#addliquidity
        dexRouter.addLiquidityETH{ value: bnbAmount }(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityAddress == DEAD_ADDRESS ? _msgSender() : liquidityAddress,
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
                if(compareStrings(_value, "Cake-LP")) // if the contract has symbol and the name is Cake-LP, it is a pancake pair
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

    function getTokenAddressFromPair(address pairAddr) internal returns (address){
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        if(pair.token0() == address(this))
            return pair.token1();
        else if(pair.token1() == address(this))
            return pair.token0();
        revert("not a pair");
    }

    function getTokenVolumeFromPair(address pairAddr) internal returns (uint256){
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddr).getReserves();

        if(pair.token0() == address(this))
            return reserve0;
        else if(pair.token1() == address(this))
            return reserve1;
        revert("not a pair");
    }

    function timeLockCheck(address from, address to) internal {
        // timelock dex transactions
        if(automatedMarketMakerPairs[to]) { // selling tokens
            require(canOperate(from), "the sender cannot operate yet");
            lockToOperate(from);
        } else if(automatedMarketMakerPairs[from]) { // buying tokens
            require(canOperate(to), "the recipient cannot sell yet");
            lockToOperate(to);
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override
    _checkIfPairIsAuthorized(from, to) // todo: test this better
    {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];

        if (excludedAccount) {
            super._transfer(from, to, amount);
        } else {
            timeLockCheck(from,to);
//            if(isDexTransaction) {
//                // timelock dex transactions
//                if(automatedMarketMakerPairs[to]) { // selling tokens
//                    require(canOperate(from), "the sender cannot operate yet");
//                    lockToOperate(from);
//                } else if(automatedMarketMakerPairs[from]) { // buying tokens
//                    require(canOperate(to), "the recipient cannot sell yet");
//                    lockToOperate(to);
//                }
//
////                // antidump
////                address otherTokenFromPair = getTokenAddressFromPair();
////                // todo: make the direction agnostic. We cannot garantee in the future that the token will always be on position 0. It could be on position 1 too if a user create the pair externally.
////                uint maxTransferAmount = uint256(reserve0).mul(maxTransferFee).div(10 ** decimals()); // never divide first. You lose precision. You should multiply first and then divide. never use only 2 decimals precision, you should use 18 decimals here
////                require(amount <= maxTransferAmount, "Max transfer amount limit reached");
//            }

            uint256 tokenToEcoSystem=0;
            if (ecoSystemFee > 0) {
                tokenToEcoSystem = amount.mul(ecoSystemFee).div(10 ** decimals());
                super._transfer(from, ecoSystemAddress, tokenToEcoSystem);
            }

            uint256 tokensToLiquidity=0;
            if (liquidityFee > 0) {
                tokensToLiquidity = amount.mul(liquidityFee).div(10 ** decimals());
                super._transfer(from, address(this), tokensToLiquidity);
                _swapAndLiquify(tokensToLiquidity); // TODO: this only works on the default pair. make it work to other pairs
            }

            uint256 tokensToBurn=0;
            if (burnFee > 0) {
                tokensToBurn = amount.mul(burnFee).div(10 ** decimals());
                super._transfer(from, DEAD_ADDRESS, tokensToBurn);
            }

            // todo: test this!
//            uint256 amountMinusFees = amount.sub(tokenToEcoSystem).sub(tokensToLiquidity).sub(tokensToBurn);
//            super._transfer(from, to, amountMinusFees);
            super._transfer(from,to, amount.sub(tokenToEcoSystem).sub(tokensToLiquidity).sub(tokensToBurn));
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


    // todo: make nonReentrant
    function withdraw() onlyOwner public {
        uint256 balance = address(this).balance;
        Address.sendValue(payable(msg.sender), balance);
    }

    // todo: make nonReentrant
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