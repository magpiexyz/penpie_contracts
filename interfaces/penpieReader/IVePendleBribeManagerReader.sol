// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVePendleBribeManagerReader {
    function getCurrentEpochEndTime() external view returns(uint256 endTime);
    struct IBribe {
        address _token;
        uint256 _amount;
    } 
    function getBribesInAllPools(uint256 _epoch) external view returns (IBribe[][] memory);
    function exactCurrentEpoch() external view returns(uint256);
    function getApprovedTokens() external view returns(address[] memory);
    function getPoolLength() external view returns(uint256);
    struct Pool {
        address _market;
        bool _active;
        uint256 _chainId;
    }
    function pools(uint256) external view returns(Pool memory);
    function getPoolList() external view returns(Pool[] memory);
}