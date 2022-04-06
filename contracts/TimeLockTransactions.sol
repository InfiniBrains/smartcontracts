// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

//import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TimeLockTransactions {
    mapping (address => uint) private walletToTime;

    uint private constant MAX_ALLOWED_TIME = 1 days;
    uint private _lockTime = 5 minutes; // 5 minutes is the default

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

    function lockIfCanOperateAndRevertIfNotAllowed(address addr) internal {
        require(canOperate(addr), "TimeLock: the sender cannot operate yet");
        lockToOperate(addr);
    }

    // @dev if you are inheriting this contract, you should expose this function and protect it via onlyowner or roles
    function _setLockTime(uint timeBetweenTransactions) internal {
        require(timeBetweenTransactions <= MAX_ALLOWED_TIME, "TimeLock: max temp ban greater than the allowed");
        _lockTime = timeBetweenTransactions;
        emit SetLockTimeEvent(timeBetweenTransactions);
    }

//    function _transfer(
//        address from,
//        address to,
//        uint256 amount
//    ) internal override {
//        require(canOperate(from), "TimeLock: the sender cannot operate yet");
//        lockToOperate(from);
//        super._transfer(from,to,amount);
//    }

    event SetLockTimeEvent(uint timeBetweenPurchases);
}
