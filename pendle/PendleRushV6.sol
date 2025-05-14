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
import "../interfaces/ISmartPendleConvert.sol";
import "../interfaces/pendle/IPendleMarketDepositHelper.sol";
import "../interfaces/pendle/IPendleRouter.sol";

/// @title PendleRush6
/// @notice Contract for calculating incentive deposits and rewards points with the Pendle token
contract PendleRush6 is
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
        uint256 convertedTimes;
        uint256 bonusRewardClaimed;
        bool isBlacklisted;
    }

    IERC20 public PENDLE; // Pendle token
    address public mPENDLE; // Pendle tokenv
    ILocker public mPendleSV;
    IERC20 public ARB; // Arbitrum token
    address public smartConvert;
    address public mPendleConvertor;
    address public mPendleMarket;
    address public pendleMarketDepositHelper;
    address public pendleStaking;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public tierLength;
    uint256 public totalAccumulated;

    uint256[] public rewardMultiplier;
    uint256[] public rewardTier;

    mapping(address => UserInfo) public userInfos; // Total conversion amount per user

    IPendleRouter public pendleRouter;

    uint256 public constant CONVERT_TO_MPENDLE = 1;
    uint256 public constant LIQUIDATE_TO_PENDLE_FINANCE = 2;
    uint256 public convertedTimesThreshold;

    struct pendleDexApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffChain;
        uint256 maxIteration;
        uint256 eps;
    }

    uint256 public smartConvertProportion; 
    uint256 public lockMPendleProportion;

    /* ========= 1st upgrade ========= */
    ILocker public boostToken;
    uint256 public boostTokenTierLength;
    uint256[] public boostTokenRewardMultiplier;
    uint256[] public boostTokenRewardTier;
    
    /* ========= 2nd upgrade ========= */
    uint256 public treasuryFee;

    /* ============ Events ============ */

    event ARBRewarded(address indexed _beneficiary, uint256 _ARBAmount);
    event PendleConverted(address indexed _account, uint256 _pendleAmount, uint256 _mPendleAmount, uint256 _smartConvertProportion, uint256 _directConvertProportion);
    event mPendleLocked(address indexed _account, uint256 _amount);
    event pendleRouterSet(address pendleRouter);
    event pendleStakingSet(address pendleStaking);
    event mPendleLiquidateToMarket(address indexed _account, uint256 _amount);
    event smartConvertProportionSet(uint256 _smartConvertProportion);
    event lockMPendleProportionSet(uint256 _lockMPendleProportion);
    event convertedTimesThresholdSet(uint256 _threshold);
    event userBlacklistUpdate(address indexed _user, bool _isBlacklisted);
    event mPendleConvertorSet(address indexed _mPENDLE, address indexed _mPendleConvertor);
    event mPendleMarketAddressSet(address indexed _mPendleMarket);
    event boostTokenUpdated(address indexed _oldBoostToken , address indexed _newBoostToken);
    event treasuryFeeSet(uint256 _treasuryFee);

    /* ============ Errors ============ */

    error InvalidAmount();
    error LengthMismatch();
    error mPendleMarketNotSet();
    error IsNotSmartContractAddress();
    error InvalidConvertMode();
    error InvalidConvertor();
    error RewardTierNotSet();
    error InvalidBoostTokenAmount();
    error BoostTokenLengthMismatch();
    error BoostTokenRewardTierNotSet();
    error AddressZero();

    /* ============ Constructor ============ */
    constructor() {
        _disableInitializers();
    }

    /* ============ Initialization ============ */

    function _PendleRush6_init(
        address _pendle,
        address _smartConvert,
        address _ARB,
        address _mPendleSV,
        address _pendleRouter,
        address _pendleMarketDepositHelper,
        address _PendleStaking,
        address _boostToken
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        PENDLE = IERC20(_pendle);
        ARB = IERC20(_ARB);
        mPendleSV = ILocker(_mPendleSV);
        pendleRouter = IPendleRouter(_pendleRouter);
        smartConvert = _smartConvert;
        pendleMarketDepositHelper = _pendleMarketDepositHelper;
        pendleStaking = _PendleStaking;
        boostToken = ILocker(_boostToken);
    }

    /* ============ External Read Functions ============ */

    function quoteConvert(
        uint256 _amountToConvert,
        address _account
    ) external view returns (uint256 rewardToSend, uint256 bonusARBReward) {
        if (rewardTier.length == 0) revert RewardTierNotSet();
        if (boostTokenRewardTier.length == 0) revert BoostTokenRewardTierNotSet();
        UserInfo memory userInfo = userInfos[_account];
        uint256 arbReward = 0;

        uint256 accumulatedRewards = _amountToConvert + userInfo.converted;
        uint256 i = 1;

        while (i < rewardTier.length && accumulatedRewards > rewardTier[i]) {
            arbReward += (rewardTier[i] - rewardTier[i - 1]) * rewardMultiplier[i - 1];
            ++i;
        }
        arbReward += (accumulatedRewards - rewardTier[i - 1]) * rewardMultiplier[i - 1];
        arbReward = (arbReward / DENOMINATOR) - userInfo.rewardClaimed;

        uint256 boostTokenBonusMultiplier = 0;
        uint256 boostTokenBalance = boostToken.getUserTotalLocked(_account);
        uint256 j = 0;

        while (j < boostTokenRewardTier.length && boostTokenBalance > boostTokenRewardTier[j]) {
            boostTokenBonusMultiplier = boostTokenRewardMultiplier[j];
            ++j;
        }
        
        uint256 bonusReward = (arbReward * boostTokenBonusMultiplier) / DENOMINATOR;
        uint256 arbleft = ARB.balanceOf(address(this));
        
        if (arbReward > arbleft) {
            return (arbleft, 0);
        }
        if (arbReward + bonusReward > arbleft) {
            bonusReward = arbleft - arbReward;
            arbReward += bonusReward;
            return (arbReward, bonusReward);
        }
        arbReward += bonusReward;
        return (arbReward, bonusReward);
    }

    function getUserTier(address _account) public view returns (uint256) {
        if (rewardTier.length == 0) revert RewardTierNotSet();
        uint256 userconverted = userInfos[_account].converted;
        for (uint256 i = tierLength - 1; i >= 1; --i) {
            if (userconverted >= rewardTier[i]) {
                return i;
            }
        }
        return 0;
    }

    function amountToNextTier(address _account) external view returns (uint256) {
        uint256 userTier = getUserTier(_account);
        if (userTier == tierLength - 1) return 0;

        return rewardTier[userTier + 1] - userInfos[_account].converted;
    }

    function validConvertor(address _user) external view returns (bool) {
        UserInfo storage userInfo = userInfos[_user];

        if (userInfo.isBlacklisted || userInfo.convertedTimes >= convertedTimesThreshold)
            return false;

        return true;
    }

    /* ============ External Write Functions ============ */

    function convert(
        uint256 _amount,
        pendleDexApproxParams memory _pdexparams,
        uint256 _convertMode
    ) external whenNotPaused nonReentrant {
        if (!this.validConvertor(msg.sender)) revert InvalidConvertor();

        if (mPendleMarket == address(0)) revert mPendleMarketNotSet();

        (uint256 rewardToSend, uint256 bonusARBReward) = this.quoteConvert(_amount, msg.sender);

        _convert(msg.sender, _amount);
        uint256 treasuryFeeAmount = (IERC20(mPENDLE).balanceOf(address(this)) - _amount) * treasuryFee / DENOMINATOR;
        uint256 mPendleToTransfer = _mPendleTransferAndLock(msg.sender, IERC20(mPENDLE).balanceOf(address(this)) - treasuryFeeAmount);

        if (mPendleToTransfer > 0) {
            if (_convertMode == CONVERT_TO_MPENDLE) {
                IERC20(mPENDLE).safeTransfer(msg.sender, mPendleToTransfer);
            } else if (_convertMode == LIQUIDATE_TO_PENDLE_FINANCE) {
                _ZapInmPendleToMarket(mPendleToTransfer, _pdexparams);
            } else {
                revert InvalidConvertMode();
            }
        }

        if (treasuryFeeAmount > 0){
            IERC20(mPENDLE).safeTransfer(owner(), treasuryFeeAmount);
        }

        UserInfo storage userInfo = userInfos[msg.sender];
        userInfo.converted += _amount;
        userInfo.rewardClaimed += (rewardToSend - bonusARBReward);
        userInfo.bonusRewardClaimed += bonusARBReward;
        totalAccumulated += _amount;
        userInfo.convertedTimes += 1;

        ARB.safeTransfer(msg.sender, rewardToSend);

        emit ARBRewarded(msg.sender, rewardToSend);
    }

    /* ============ Internal Functions ============ */

    function _convert(address _account, uint256 _amount) internal {
        PENDLE.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 smartAmount = _amount * smartConvertProportion / DENOMINATOR;
        uint256 directAmount = _amount - smartAmount;

        if (directAmount > 0) {
            PENDLE.safeApprove(mPendleConvertor, directAmount);
            IConvertor(mPendleConvertor).convert(address(this), directAmount, 0);
        }

        if (smartAmount > 0) {
            PENDLE.safeApprove(smartConvert, smartAmount);
            ISmartPendleConvert(smartConvert).smartConvert(smartAmount, 0);
        }

        emit PendleConverted(_account, _amount, IERC20(mPENDLE).balanceOf(address(this)), smartConvertProportion, DENOMINATOR - smartConvertProportion);
    }

    function _lock(address _account, uint256 _amount) internal {
        IERC20(mPENDLE).safeApprove(address(mPendleSV), _amount);
        mPendleSV.lockFor(_amount, _account);

        emit mPendleLocked(_account, _amount);

    }

    function _ZapInmPendleToMarket(
        uint256 mPendleAmount,
        pendleDexApproxParams memory _pdexparams
    ) internal {
        IERC20(mPENDLE).safeApprove(address(pendleRouter), 0);
        IERC20(mPENDLE).safeApprove(address(pendleRouter), mPendleAmount);

        (uint256 netLpOut, ) = pendleRouter.addLiquiditySingleToken(
            address(this),
            mPendleMarket,
            type(uint256).min,
            IPendleRouter.ApproxParams(
                _pdexparams.guessMin,
                _pdexparams.guessMax,
                _pdexparams.guessOffChain,
                _pdexparams.maxIteration,
                _pdexparams.eps
            ),
            IPendleRouter.TokenInput(
                mPENDLE,
                mPendleAmount,
                mPENDLE,
                address(0),
                address(0),
                IPendleRouter.SwapData(IPendleRouter.SwapType.NONE, address(0), "0x", false)
            )
        );
        IERC20(mPendleMarket).safeApprove(pendleStaking, netLpOut);
        IPendleMarketDepositHelper(pendleMarketDepositHelper).depositMarketFor(
            mPendleMarket,
            msg.sender,
            netLpOut
        );

        emit mPendleLiquidateToMarket(msg.sender, mPendleAmount);
    }

    /* ============ Private Functions ============ */ 

    function _mPendleTransferAndLock(
        address _for,
        uint256 mPendle
    ) private returns (uint256) {
        uint256 mPendleToLock = mPendle * lockMPendleProportion / DENOMINATOR;
        uint256 mPendleToTransfer = mPendle - mPendleToLock;

        if (mPendleToLock > 0) {
            _lock(_for, mPendleToLock);
        }

        return mPendleToTransfer;
    }

    /* ============ Admin Functions ============ */

    function setConvertedTimesThreshold(uint256 _threshold) external onlyOwner {
        convertedTimesThreshold = _threshold;
        emit convertedTimesThresholdSet(_threshold);
    }

    function updateUserBlacklist(address _user, bool _isBlacklisted) external onlyOwner {
        UserInfo storage userInfo = userInfos[_user];

        userInfo.isBlacklisted = _isBlacklisted;
        emit userBlacklistUpdate(_user, _isBlacklisted);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMPendleConvertor(address _mPENDLE, address _mPendleConvertor) external onlyOwner {
        mPENDLE = _mPENDLE;
        mPendleConvertor = _mPendleConvertor;
        emit mPendleConvertorSet(_mPENDLE, _mPendleConvertor);
    }

    function setPendleStaking(address _PendleStaking) external onlyOwner {
        if (!Address.isContract(_PendleStaking)) revert IsNotSmartContractAddress();

        pendleStaking = _PendleStaking;
        emit pendleStakingSet(pendleStaking);
    }

    function setMPendleMarketAddress(address _mPendleMarket) external onlyOwner {
        mPendleMarket = _mPendleMarket;
        emit mPendleMarketAddressSet(_mPendleMarket);
    }

    function setBoostToken(address _newBoostToken) external onlyOwner {
        if (_newBoostToken == address(0)) revert AddressZero();

        address _oldBoostToken = address(boostToken);
        boostToken = ILocker(_newBoostToken);

        emit boostTokenUpdated(_oldBoostToken, _newBoostToken);
    }

    function setSmartConvertProportion(uint256 _smartConvertProportion) external onlyOwner {
        require(_smartConvertProportion <= DENOMINATOR, "Smart convert Proportion cannot be greater than 100%.");
        smartConvertProportion = _smartConvertProportion;
        emit smartConvertProportionSet(_smartConvertProportion);
    }

    function setLockMPendleProportion(uint256 _lockMPendleProportion) external onlyOwner {
        require(_lockMPendleProportion <= DENOMINATOR, "Lock mPendle Proportion cannot be greater than 100%."); 
        lockMPendleProportion = _lockMPendleProportion;
        emit lockMPendleProportionSet(_lockMPendleProportion);
    }

    function setTreasuryFee(uint256 _treasuryFee) external onlyOwner {
        require(_treasuryFee <= DENOMINATOR, "Treasury Fee Proportion cannot be greater than 100%."); 
        treasuryFee = _treasuryFee;
        emit treasuryFeeSet(_treasuryFee);
    }

    function setPendleRouter(address _pendleRouter) external onlyOwner {
        if (!Address.isContract(_pendleRouter)) revert IsNotSmartContractAddress();

        pendleRouter = IPendleRouter(_pendleRouter);

        emit pendleRouterSet(_pendleRouter);
    }

    function setMultiplier(
        uint256[] calldata _multiplier,
        uint256[] calldata _tier
    ) external onlyOwner {
        if (_multiplier.length == 0 || _tier.length == 0 || (_multiplier.length != _tier.length))
            revert LengthMismatch();

        for (uint8 i; i < _multiplier.length; ++i) {
            if (_multiplier[i] == 0) revert InvalidAmount();
            if (i > 0) {
                require(_tier[i] > _tier[i-1], "Reward tier values must be in increasing order.");
            }
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

    function setBoostTokenMultiplier(
        uint256[] calldata _boostTokenmultiplier,
        uint256[] calldata _boostTokentier
    ) external onlyOwner {
        if (_boostTokenmultiplier.length == 0 || _boostTokentier.length == 0 || (_boostTokenmultiplier.length != _boostTokentier.length))
            revert BoostTokenLengthMismatch();

        for (uint8 i; i < _boostTokenmultiplier.length; ++i) {
            if (_boostTokenmultiplier[i] == 0) revert InvalidBoostTokenAmount();
            if (i > 0) {
                require(_boostTokentier[i] > _boostTokentier[i-1], "Boost Token reward tier values must be in increasing order.");
            }
            boostTokenRewardMultiplier.push(_boostTokenmultiplier[i]);
            boostTokenRewardTier.push(_boostTokentier[i]);
            boostTokenTierLength += 1;
        }
    }

    function resetBoostTokenMultiplier() external onlyOwner {
        uint256 len = boostTokenRewardMultiplier.length;
        for (uint8 i = 0; i < len; ++i) {
            boostTokenRewardMultiplier.pop();
            boostTokenRewardTier.pop();
        }

        boostTokenTierLength = 0;
    }

    function adminWithdrawTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}
