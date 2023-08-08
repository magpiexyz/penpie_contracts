// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/ERC20.sol)
pragma solidity ^0.8.0;

import { IMintableERC20 } from "../../interfaces/IMintableERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract PendleMarketMock is ERC20, Ownable {
    struct UserReward {
        uint256 latestUpdated;
        uint256 accrued;
    }

    struct RewardState {
        uint256 index;
        uint256 lastBalance;
    }

    uint256 constant rewardAmt = 1e18;

    address[] public rewardTokens;
    mapping(address => mapping(address => UserReward)) public userReward;
    mapping(address => RewardState) public rewardState;
    uint256 public rewardDuration; // New variable to set the reward duration

    constructor() ERC20("PMT", "PMT") {}

    function addReward(address _token) external {
        rewardTokens.push(_token);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function setDuration(uint256 _rewardDuration) external {
        require(_rewardDuration > 0);
        rewardDuration = _rewardDuration;
    }

    function redeemRewards(
        address user
    ) external returns (uint256[] memory rewardAmounts) {
        _updateAndDistributeRewards(user);

        rewardAmounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewardAmounts[i] = userReward[rewardTokens[i]][user].accrued;
            if (rewardAmounts[i] != 0) {
                userReward[rewardTokens[i]][user].accrued = 0;
                // rewardState[rewardTokens[i]].lastBalance -= rewardAmounts[i];
                _transferOut(rewardTokens[i], user, rewardAmounts[i]);
            }
        }
    }

    function _transferOut(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        IMintableERC20(_token).mint(_to, _amount);
    }

    function mint(address account, uint256 amount) external virtual onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external virtual onlyOwner {
        _burn(account, amount);
    }

    function _updateAndDistributeRewards(address user) private {
        assert(user != address(0) && user != address(this));
        if (rewardTokens.length == 0) return;
        uint256 currentTimestamp = block.timestamp;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            UserReward storage reward = userReward[rewardTokens[i]][user];
            uint256 timeDiff = currentTimestamp - reward.latestUpdated;
            if (timeDiff > rewardDuration && reward.latestUpdated > 0) {
                uint256 rewardAmount = (timeDiff - rewardDuration) * rewardAmt;
                reward.accrued += rewardAmount;
                reward.latestUpdated = currentTimestamp;
            } else if (reward.latestUpdated == 0) {
                reward.latestUpdated = currentTimestamp;
            }
        }
    }
}
