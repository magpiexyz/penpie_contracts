// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "./IBaseRewardPool.sol";
import "./IBribeRewardDistributor.sol";

interface IVLPenpieBaseRewarder is IBaseRewardPool {
    function rewardTokenInfosWithBribe(IBribeRewardDistributor.Claim[] calldata _proof) external view
        returns (
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols
        );
    
    function rewardTokenInfos() external view
        returns (
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols
        );
    
    function allEarnedWithBribe(address _account, IBribeRewardDistributor.Claim[] calldata _proof) external view
        returns (uint256[] memory pendingBonusRewards);
    
    function allEarned(address _account) external view
        returns (uint256[] memory pendingBonusRewards);
    
    function getReward(
        address _account,
        address _receiver
    ) external returns (bool);
    
    function queuePenpie(uint256 _amount, address _user, address _receiver) external returns(bool);
}