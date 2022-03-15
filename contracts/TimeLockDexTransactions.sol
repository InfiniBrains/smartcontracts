// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

contract TimeLockDexTransactions {
    mapping (address => uint) private walletToTime;

    uint private immutable _maxAllowedTime = 1 days;
    uint private _lockTime = 0; // 0 s per transaciton

    function getLockTime() external view returns(uint){
        return _lockTime;
    }

    function getFromLastTransaction(address wallet) public view returns (uint) {
        return walletToTime[wallet];
    }

    function lockToOperate(address addr) internal {
        walletToTime[addr] = block.timestamp + _lockTime;
    }

    function canOperate(address addr) public view returns (bool){
        return walletToTime[addr] <= block.timestamp;
    }

    function _setLockTime(uint timeBetweenTransactions) internal {
        require(timeBetweenTransactions <= _maxAllowedTime, "max temp ban greater than the allowed");
        _lockTime = timeBetweenTransactions;
        emit SetLockTimeEvent(timeBetweenTransactions);
    }
    event SetLockTimeEvent(uint timeBetweenPurchases);
}
