// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IBatchAddBribe {
    struct Bribe {
        address token;
        uint256 amount;
    }

    struct Reward {
        uint256 periodFinish;
        uint256 rewardsPerEpoch;
        uint256 lastUpdateTime; 
    }

    error InvalidPool();
    
    function addBribeERC20(uint256 _batch, uint256 _pid, address _token, uint256 _amount, bool _forPreviousEpoch) external;

    function addBribeERC20(uint256 _batch,address _pool,address _token,uint256 _amount,bool _forPreviousEpoch,bool _forVeCake) external;

    function addBribeERC20(uint16 _distributorId, address _token, uint256 _amount, uint256 _startingEpoch, uint256 _numOfEpochs) external;

    function addBribeERC20ForVePendle(uint256 _batch, uint256 _pid, address _token, uint256 _amount, bool _forPreviousEpoch) external; 
    
    function updateAllowedOperator(address _user, bool _allowed) external;

    function getCurrentEpochEndTime() external view returns(uint256 endTime);

    function getCurrentEpoch() external view returns(uint256 epoch);

    function getBribesInPool( uint256 _targetTime, address _pool ) external view returns (Bribe[] memory);
    
    function getBribesInPoolForVeCake( uint256 _targetTime, address _pool ) external view returns (Bribe[] memory);

    function getCurrentPeriodEndTime() external view returns (uint256 endTime);

    function notifyRewardAmount(address _rewardsToken, uint256 reward) external;

    function bribes(uint256 _epoch, uint16 _pid, address _token) external view returns (uint256);

    function active_period() external view returns(uint);

    function minter() external view returns(address);

    function rewardData(address _token, uint startTime) external view returns(Reward memory);
}