// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

contract TimeLockDexTransactions {
    mapping (address => uint) private walletToPurchaseTime;
    mapping (address => uint) private walletToSellime;

    uint immutable maxAllowedTime = 1 days;
    uint private sellTime = 0; // 0 s per transaciton
    uint private buyTime = 0; // 0 s per transaciton

    function getSellTime() external view returns(uint){
        return sellTime;
    }
    function getButTime() external view returns(uint){
        return buyTime;
    }

    function getFromLastBuy(address wallet) public view returns (uint) {
        return walletToPurchaseTime[wallet];
    }
    function getFromLastSell(address walletSell) public view returns (uint) {
        return walletToSellime[walletSell];
    }

    function lockToBuy(address addr) internal {
        walletToPurchaseTime[addr] = block.timestamp + 1 days;
    }
    function lockToSell(address addr) internal {
        walletToSellime[addr] = block.timestamp + 1 days;
    }

    function canBuy(address addr) public view returns (bool){
        return walletToPurchaseTime[addr] <= block.timestamp;
    }
    function canSell(address addr) public view returns (bool){
        return walletToSellime[addr] <= block.timestamp;
    }

//    function lockToBuyOrSellForTime(uint256 lastBuyOrSellTime, uint256 lockTime) public view returns (bool) {
//        if( lastBuyOrSellTime == 0 ) return true;
//        uint256 crashTime = block.timestamp - lastBuyOrSellTime;
//        if( crashTime >= lockTime ) return true;
//        return false;
//    }

    function _setBuyTime(uint timeBetweenPurchases) internal {
        require(timeBetweenPurchases <= maxAllowedTime, "max temp ban greater than the allowed");
        buyTime = timeBetweenPurchases;
        emit SetBuyTimeEvent(timeBetweenPurchases);
    }
    event SetBuyTimeEvent(uint timeBetweenPurchases);

    function _setSellTime(uint timeBetweenSell) internal {
        require(timeBetweenSell <= maxAllowedTime, "max temp ban greater than the allowed");
        sellTime = timeBetweenSell;
        emit SetSellTimeEvent(timeBetweenSell);
    }
    event SetSellTimeEvent(uint timeBetweenSell);
}
