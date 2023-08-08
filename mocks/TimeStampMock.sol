// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/WeekMath.sol";

contract TimeStampMock {
    function getCurrentTime() external view returns (uint128) {
        return WeekMath.getWeekStartTimestamp(uint128(block.timestamp));
    }

    function _getIncreaseLockTime(
        uint128 _lockPeriod
    ) external view returns (uint128) {
        return
            WeekMath.getWeekStartTimestamp(
                uint128(block.timestamp + _lockPeriod)
            );
    }
}
