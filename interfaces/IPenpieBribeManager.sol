// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IPenpieBribeManager {
    function marketToPid(address _market) external view returns(uint256);
    function exactCurrentEpoch() external view returns(uint256);
    function getEpochEndTime(uint256 _epoch) external view returns(uint256 endTime);
    function addBribeERC20(uint256 _batch, uint256 _pid, address _token, uint256 _amount) external;
    function addBribeNative(uint256 _batch, uint256 _pid) external payable;
}