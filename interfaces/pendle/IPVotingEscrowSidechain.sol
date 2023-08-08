// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.19;

import "./IPVeToken.sol";
import "../../libraries/VeBalanceLib.sol";
import "../../libraries/VeHistoryLib.sol";

interface IPVotingEscrowSidechain is IPVeToken {
    function totalSupplyAt(uint128 timestamp) external view returns (uint128);

    function getUserHistoryLength(address user) external view returns (uint256);

    function getUserHistoryAt(
        address user,
        uint256 index
    ) external view returns (Checkpoint memory);
    
    function getBroadcastPositionFee(uint256[] calldata chainIds) external view returns (uint256 fee);

    function totalSupplyCurrent() external view returns (uint128);

    function balanceOf(address user) external view returns (uint128);

}
