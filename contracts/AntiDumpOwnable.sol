// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

// @dev all decimals here are 18
contract AntiDumpOwnable is Ownable{
    using SafeMath for uint256;
    using Address for address;

    // @dev antidump mechanics
    uint256 public antiDumpThreshold; // 0.5%

    // @dev antidump mechanics
    uint256 public antiDumpFee; // 25%

    // @dev antidump mechanics
    uint256 public immutable ANTI_DUMP_THRESHOLD_LIMIT; // 0.1%

    // @dev antidump mechanics the total max value of the extra fees
    uint256 public immutable ANTI_DUMP_FEE_LIMIT; // 25%

    constructor(uint256 decimals) {
        antiDumpThreshold = 5 * 10**(decimals-3); // 0.5%

        antiDumpFee = 25 * 10**(decimals-2); // 25%

        ANTI_DUMP_THRESHOLD_LIMIT = 1 * 10**(decimals-3); // 0.1%

        ANTI_DUMP_FEE_LIMIT = 25 * 10**(decimals-2); // 25%
    }

    function setAntiDumpThreshold(uint256 newThreshold) public onlyOwner {
        require(newThreshold >= ANTI_DUMP_THRESHOLD_LIMIT, "The company cannot set abusive threshold");
        antiDumpThreshold = newThreshold;
        emit AntiDumpThresholdUpdated(newThreshold);
    }
    event AntiDumpThresholdUpdated(uint256 indexed threshold);

    function setAntiDump(uint256 newThreshold, uint256 newFee) external onlyOwner {
        require(newThreshold >= ANTI_DUMP_THRESHOLD_LIMIT, "new threshold is not acceptable");
        require(newFee<=ANTI_DUMP_FEE_LIMIT, "new fee is not acceptable");

        antiDumpThreshold = newThreshold;
        antiDumpFee = newFee;

        emit SetAntiDump(newThreshold, newFee);
    }
    event SetAntiDump(uint256 newThreshold, uint256 newfee);

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

    function getAntiDumpFee(address pair, uint256 amount) internal view returns(uint256) {
        uint256 volume = getTokenVolumeFromPair(pair);
        if (volume > 0) {
            uint256 maxVolume = volume.mul(antiDumpThreshold).div(10**18);
            if (amount >= maxVolume)
                return antiDumpFee;
        }
        return 0;
    }
}