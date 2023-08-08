// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IPendleStakingMeta {
    struct PendleStakingPoolInfo {
        address market;
        address rewarder;
        address helper;
        address receiptToken;
        uint256 lastHarvestTime;
        bool isActive;
    }
    function pools(address) external view returns (PendleStakingPoolInfo memory);
    function mPendleOFT() external view returns (address);
    function PENDLE() external view returns (address);
    function WETH() external view returns (address);
    function mPendleConvertor() external view returns (address);
}