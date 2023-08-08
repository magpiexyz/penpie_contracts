// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../interfaces/ILocker.sol";
import "../interfaces/IConvertor.sol";

/// @title PendleRush4
/// @notice Contract for calculating incentive deposits and rewards points with the Pendle token
contract PendleRush4 is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct UserInfo {
        uint256 converted;
        uint256 rewardClaimed;
    }    

    IERC20 public PENDLE; // Pendle token
    IERC20 public mPENDLE; // Pendle tokenv
    IERC20 public PNP;    // Penpie token
    ILocker public vlPNP; 
    ILocker public mPendleSV; 
    address public smartConvert;
    address public mPendleConvertor;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public tierLength;
    uint256 public totalAccumulated;
    
    uint256[] public rewardMultiplier;
    uint256[] public rewardTier;

    mapping(address => UserInfo) public userInfos; // Total conversion amount per user

    /* ============ Events ============ */

    event VLPNPRewarded(address indexed _beneficiary, uint256 _vlPNPAmount);
    event PendleConverted(address indexed _account, uint256 _amount, uint256 _mode);

    /* ============ Errors ============ */

    error InvalidAmount();
    error LengthMissmatch();    

    /* ============ Constructor ============ */
    constructor() {
        _disableInitializers();
    }

    /* ============ Initialization ============ */

    function _PendleRush4_init(
        address _pendle,
        address _smartConvert,
        address _vlPNP,
        address _PNP,
        address _mPendleSV
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        PENDLE = IERC20(_pendle);
        vlPNP = ILocker(_vlPNP); 
        smartConvert = _smartConvert;
        PNP = IERC20(_PNP);
        mPendleSV = ILocker(_mPendleSV);
    }

    /* ============ External Read Functions ============ */

    function quoteDeposit(
        uint256 _amount,
        address _account,
        bool _lock
    ) public view returns (uint256) {
        uint256 pnpReward = 0;

        if (!_lock) {
           pnpReward = _amount * rewardMultiplier[getUserTier(_account)] / DENOMINATOR;
        } else {
           uint256 accumulated = _amount + mPendleSV.getUserTotalLocked(_account);
           uint256 rewardAmount = 0;
           uint256 i = 1;

           while (i < rewardTier.length && accumulated > rewardTier[i]) {
               rewardAmount += (rewardTier[i] - rewardTier[i - 1]) * rewardMultiplier[i - 1];
               i++;
            }
           rewardAmount += (accumulated - rewardTier[i - 1]) * rewardMultiplier[i - 1];
           pnpReward = (rewardAmount / DENOMINATOR) - calDoubledCounted(_account);
        }
        uint256 pnpleft = IERC20(PNP).balanceOf(address(this));
        uint256 finalReward = pnpReward > pnpleft ? pnpleft : pnpReward;
        return finalReward;
    }

    function calDoubledCounted(address _account) public view returns (uint256) {
        uint256 accuIn1 = mPendleSV.getUserTotalLocked(_account);
        uint256 rewardAmount = 0;
        uint256 i = 1;
        while (i < rewardTier.length && accuIn1 > rewardTier[i]) {
            rewardAmount +=
                (rewardTier[i] - rewardTier[i - 1]) *
                rewardMultiplier[i - 1];
            i++;
        }

        rewardAmount += (accuIn1 - rewardTier[i - 1]) * rewardMultiplier[i - 1];
        return rewardAmount / DENOMINATOR;
    }     

    function getUserTier(address _account) public view returns (uint256) {
        uint256 userDeposited = userInfos[_account].converted;
        for (uint256 i = tierLength - 1; i >= 1; i--) {
            if (userDeposited >= rewardTier[i]) {
                return i;
            }
        }

        return 0;
    }

    function amountToNextTier(
        address _account
    ) external view returns (uint256) {
        uint256 userTier = this.getUserTier(_account);
        if (userTier == tierLength - 1) return 0;

        return rewardTier[userTier + 1] - userInfos[_account].converted;
    }

    /* ============ External Write Functions ============ */

    function deposit(       
        uint256 _amount,
       uint256 _convertRatio,
       uint256 _mode  // 1 stake, 2 lock 
       ) external whenNotPaused nonReentrant {

       uint256 rewardToSend = this.quoteDeposit(_amount, msg.sender, _mode == 2);

       _deposit(msg.sender, _convertRatio, _amount, _mode);

        UserInfo storage userInfo = userInfos[msg.sender];
        userInfo.converted += _amount;
        userInfo.rewardClaimed += rewardToSend;
        totalAccumulated += _amount;

        // Lock the rewarded vlPNP
       IERC20(PNP).safeApprove(address(vlPNP), rewardToSend);
       vlPNP.lockFor(rewardToSend, msg.sender);
       
       emit VLPNPRewarded(msg.sender, rewardToSend);
    }

    /* ============ Internal Functions ============ */

    function _deposit(address _account, uint256 _convertRatio, uint256 _amount, uint256 _mode) internal {
        IERC20(PENDLE).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 directAmount = _amount / 2;
        uint256 smartAmount = _amount - directAmount;

        // 50% direct
        IERC20(PENDLE).safeApprove(mPendleConvertor, directAmount);
        IConvertor(mPendleConvertor).convert(_account, directAmount, _mode);

        // 50% smart convert
        IERC20(PENDLE).safeApprove(smartConvert, smartAmount);
        IConvertor(smartConvert).convertFor(smartAmount, _convertRatio, 0, _account, _mode);

        emit PendleConverted(_account, _amount, _mode);
    }    

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMPendleConvertor(address _mPENDLE, address _mPendleConvertor) external onlyOwner {
        mPENDLE = IERC20(_mPENDLE);
        mPendleConvertor = _mPendleConvertor;
    }

    function setMultiplier(
        uint256[] calldata _multiplier,
        uint256[] calldata _tier
    ) external onlyOwner {
        if (
            _multiplier.length == 0 ||
            _tier.length == 0 ||
            (_multiplier.length != _tier.length)
        ) revert LengthMissmatch();

        for (uint8 i ; i < _multiplier.length; ++i) {
            if (_multiplier[i] == 0) revert InvalidAmount();
            rewardMultiplier.push(_multiplier[i]);
            rewardTier.push(_tier[i]);
            tierLength += 1;
        }
    }

    function resetMultiplier() external onlyOwner {
        uint256 len = rewardMultiplier.length;
        for (uint8 i = 0; i < len; ++i) {
            rewardMultiplier.pop();
            rewardTier.pop();
        }

        tierLength = 0;
    }

    function adminWithdrawTokens(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}