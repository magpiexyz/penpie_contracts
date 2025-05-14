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

/// @title PendleRush5
/// @notice Contract for calculating incentive deposits and rewards points with the Pendle token
contract PendleRush5 is
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
        bool isBlacklisted;
    }

    IERC20 public PENDLE; // Pendle token
    address public mPENDLE; // Pendle tokenv
    IERC20 public PNP; // Penpie token
    ILocker public vlPNP;
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

    /* ============ Events ============ */

    event VLPNPRewarded(address indexed _beneficiary, uint256 _vlPNPAmount);
    event PendleConverted(address indexed _account, uint256 _amount);
    event pendleRouterSet(address pendleRouter);
    event pendleStakingSet(address pendleStaking);
    event mPendleLiquidateToMarket(address indexed _account, uint256 _amount);

    /* ============ Errors ============ */

    error InvalidAmount();
    error LengthMissmatch();
    error mPendleMarketNotSet();
    error IsNotSmartContractAddress();
    error InvalidConvertMode();
    error InvalidConvertor();

    /* ============ Constructor ============ */
    constructor() {
        _disableInitializers();
    }

    /* ============ Initialization ============ */

    function _PendleRush5_init(
        address _pendle,
        address _smartConvert,
        address _vlPNP,
        address _PNP,
        address _pendleRouter,
        address _pendleMarketDepositHelper,
        address _PendleStaking
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        PENDLE = IERC20(_pendle);
        vlPNP = ILocker(_vlPNP);
        pendleRouter = IPendleRouter(_pendleRouter);
        smartConvert = _smartConvert;
        pendleMarketDepositHelper = _pendleMarketDepositHelper;
        pendleStaking = _PendleStaking;
        PNP = IERC20(_PNP);
    }

    /* ============ External Read Functions ============ */

    function quoteConvert(
        uint256 _amountToConvert,
        address _account
    ) external view returns (uint256) {
        UserInfo memory userInfo = userInfos[_account];
        uint256 pnpReward = 0;

        uint256 accumulatedRewards = _amountToConvert + userInfo.converted;
        uint256 i = 1;

        while (i < rewardTier.length && accumulatedRewards > rewardTier[i]) {
            pnpReward += (rewardTier[i] - rewardTier[i - 1]) * rewardMultiplier[i - 1];
            i++;
        }

        pnpReward += (accumulatedRewards - rewardTier[i - 1]) * rewardMultiplier[i - 1];

        pnpReward = (pnpReward / DENOMINATOR) - userInfo.rewardClaimed;
        uint256 pnpleft = PNP.balanceOf(address(this));

        uint256 finalReward = pnpReward > pnpleft ? pnpleft : pnpReward;
        return finalReward;
    }

    function getUserTier(address _account) public view returns (uint256) {
        uint256 userconverted = userInfos[_account].converted;
        for (uint256 i = tierLength - 1; i >= 1; i--) {
            if (userconverted >= rewardTier[i]) {
                return i;
            }
        }
        return 0;
    }

    function amountToNextTier(address _account) external view returns (uint256) {
        uint256 userTier = this.getUserTier(_account);
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

        uint256 rewardToSend = this.quoteConvert(_amount, msg.sender);

        if (_convertMode == CONVERT_TO_MPENDLE) {
            _convert(msg.sender, _amount);
            IERC20(mPENDLE).safeTransfer(msg.sender, IERC20(mPENDLE).balanceOf(address(this)));
        } else if (_convertMode == LIQUIDATE_TO_PENDLE_FINANCE) {
            _convert(msg.sender, _amount);
            _ZapInmPendleToMarket(IERC20(mPENDLE).balanceOf(address(this)), _pdexparams);
        } else {
            revert InvalidConvertMode();
        }

        UserInfo storage userInfo = userInfos[msg.sender];
        userInfo.converted += _amount;
        userInfo.rewardClaimed += rewardToSend;
        totalAccumulated += _amount;
        userInfo.convertedTimes += 1;

        // Lock the rewarded vlPNP
        PNP.safeApprove(address(vlPNP), rewardToSend);
        vlPNP.lockFor(rewardToSend, msg.sender);

        emit VLPNPRewarded(msg.sender, rewardToSend);
    }

    /* ============ Internal Functions ============ */

    function _convert(address _account, uint256 _amount) internal {
        PENDLE.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 directAmount = _amount / 2;
        uint256 smartAmount = _amount - directAmount;

        // 50% direct
        PENDLE.safeApprove(mPendleConvertor, directAmount);
        IConvertor(mPendleConvertor).convert(address(this), directAmount, 0);

        // 50% smart convert
        PENDLE.safeApprove(smartConvert, smartAmount);
        ISmartPendleConvert(smartConvert).smartConvert(smartAmount, 0);

        emit PendleConverted(_account, _amount);
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

    /* ============ Admin Functions ============ */

    function setConvertedTimesThreshold(uint256 _threshold) external onlyOwner {
        convertedTimesThreshold = _threshold;
    }

    function updateUserBlacklist(address _user, bool _isBlacklisted) external onlyOwner {
        UserInfo storage userInfo = userInfos[_user];

        userInfo.isBlacklisted = _isBlacklisted;
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
    }

    function setPendleStaking(address _PendleStaking) external onlyOwner {
        if (!Address.isContract(_PendleStaking)) revert IsNotSmartContractAddress();

        pendleStaking = _PendleStaking;
        emit pendleStakingSet(pendleStaking);
    }

    function setMPendleMarketAddress(address _mPendleMarket) external onlyOwner {
        mPendleMarket = _mPendleMarket;
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
            revert LengthMissmatch();

        for (uint8 i; i < _multiplier.length; ++i) {
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

    function adminWithdrawTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}
