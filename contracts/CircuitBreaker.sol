// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Heap.sol";

// todo: add extra fee if the current price is below the thresholdCB when compared to max price of one day moving window

contract CircuitBreaker {
    using Heap for Heap.Data;
    Heap.Data public data;
    using SafeMath for uint256;

    uint32 bucketTimeLimit = 15 minutes; // 15 min
    uint32 constant BUCKET_TIME_LIMIT = 1 hours; // 1h

    uint32 bucketSizeLimit = 96; // 96*15m = 24h
    uint32 constant BUCKET_SIZE_LIMIT = 128;

    uint256 extraFeeCB = 3 * 10**17; // 30%
    uint256 EXTRA_FEE_CB_LIMIT = 4 * 10**17; // 40%

    uint256 thresholdCB = 1 * 10**17; // 10%
    uint256 THRESHOLD_CB_LIMIT = 1 * 10**16; // 1%

    constructor() public { data.init(); }

    // @dev remove buckets older than a datetime. // todo: how to do it?

    // todo: how to remove old buckets?
    // @dev Used to find the exactly bucket. It is useful to find the exacly bucket by time and remove the older ones

}