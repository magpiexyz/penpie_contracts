// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.19;

import "./IPVeToken.sol";
import "../../libraries/VeBalanceLib.sol";
import "../../libraries/VeHistoryLib.sol";

interface IPVotingEscrowMainchain is IPVeToken {
    event NewLockPosition(address indexed user, uint128 amount, uint128 expiry);

    event Withdraw(address indexed user, uint128 amount);

    event BroadcastTotalSupply(VeBalance newTotalSupply, uint256[] chainIds);

    event BroadcastUserPosition(address indexed user, uint256[] chainIds);

    // ============= ACTIONS =============

    function increaseLockPosition(
        uint128 additionalAmountToLock,
        uint128 expiry
    ) external returns (uint128);

    function increaseLockPositionAndBroadcast(
        uint128 additionalAmountToLock,
        uint128 newExpiry,
        uint256[] calldata chainIds
    ) external payable returns (uint128 newVeBalance);

    function withdraw() external returns (uint128);

    function totalSupplyAt(uint128 timestamp) external view returns (uint128);

    function getUserHistoryLength(address user) external view returns (uint256);

    function getUserHistoryAt(
        address user,
        uint256 index
    ) external view returns (Checkpoint memory);

    function broadcastUserPosition(address user, uint256[] calldata chainIds) external payable;
    
    function getBroadcastPositionFee(uint256[] calldata chainIds) external view returns (uint256 fee);

}
