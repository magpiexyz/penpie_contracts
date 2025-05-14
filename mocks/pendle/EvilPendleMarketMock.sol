// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/ERC20.sol)
pragma solidity ^0.8.0;

import { IMintableERC20 } from "../../interfaces/IMintableERC20.sol";
import "../../interfaces/pendle/IStandardizedYield.sol";
import "../../interfaces/pendle/IPPrincipalToken.sol";
import "../../interfaces/pendle/IPYieldToken.sol";
import "../../libraries/math/MarketMathCore.sol";
import "./interfaces/IPMarketFactory.sol";
import "./pendleStandardizedYield/erc20/PendleERC20Permit.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPendleMarketDepositHelper } from "../../interfaces/pendle/IPendleMarketDepositHelper.sol";

contract EvilPendleMarketMock is PendleERC20Permit, Ownable {
    IStandardizedYield public  SY;
    IPPrincipalToken public  PT;
    IPYieldToken public  YT;

    address public immutable factory;

    struct UserReward {
        uint256 latestUpdated;
        uint256 accrued;
    }

    struct RewardState {
        uint256 index;
        uint256 lastBalance;
    }

    struct MarketStorage {
        int128 totalPt;
        int128 totalSy;
        // 1 SLOT = 256 bits
        uint96 lastLnImpliedRate;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        // 1 SLOT = 144 bits
    }

    uint256 constant rewardAmt = 1e18;
    MarketStorage public _storage;


    address[] public rewardTokens;
    mapping(address => mapping(address => UserReward)) public userReward;
    mapping(address => RewardState) public rewardState;
    uint256 public rewardDuration; // New variable to set the reward duration
    address public pendleStaking;
    address public penpieDepositHelper;

    constructor(address _pendleStaking, address _depositHelper) PendleERC20Permit("PMT", "PMT", 18) {
        factory = msg.sender;
        pendleStaking = _pendleStaking;
        penpieDepositHelper = _depositHelper;
    }

    function addReward(address _token) external {
        rewardTokens.push(_token);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function setSyToken(address _sy) external 
    {
        SY = IStandardizedYield(_sy);
    }

    function setDuration(uint256 _rewardDuration) external {
        require(_rewardDuration > 0);
        rewardDuration = _rewardDuration;
    }

    function redeemRewards(
        address user
    ) external returns (uint256[] memory rewardAmounts) {
        for(uint8 idx = 0; idx < rewardTokens.length; idx ++){

            ERC20 depositToken = ERC20(rewardTokens[idx]);
            uint256 balance = depositToken.balanceOf(address(this));
            if(balance > 0)
            {
                depositToken.approve(pendleStaking, balance);
                IPendleMarketDepositHelper(penpieDepositHelper).depositMarket(rewardTokens[idx], balance);
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

    function mint(address account, uint256 amount) external virtual {
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

    function readState(address router) public view returns (MarketState memory market) {}

    function swapSyForExactPt(
        address receiver,
        uint256 exactPtOut,
        bytes calldata data
    ) external nonReentrant returns (uint256 netSyIn, uint256 netSyFee) {}

    function readTokens()
        external
        view
        returns (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT)
    {
        _SY = SY;
        _PT = IPPrincipalToken(address(0));
        _YT = IPYieldToken(address(0));
    }

    function addRewardTokens(address rewardToken) public {
        rewardTokens.push(rewardToken);
    }
}
