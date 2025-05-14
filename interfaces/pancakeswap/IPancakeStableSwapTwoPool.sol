// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

/// @title Get the expected return amount for swapping tokens via Pancake Stable Swap
/// @notice Functions for getting the expected return amount for swapping tokens via Pancake Stable Swap
interface IPancakeStableSwapTwoPool {
    function balances(uint256) external view returns (uint256);

    function get_dy(
        uint256 token0,
        uint256 token1,
        uint256 inputAmount
    ) external view returns (uint256 outputAmount);
}
