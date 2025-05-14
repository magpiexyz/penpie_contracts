// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/pancakeswap/IStableSwapRouter.sol";
import "../interfaces/pancakeswap/IPancakeStableSwapTwoPool.sol";
import "../interfaces/IConvertor.sol";
import "../interfaces/ISmartPendleConvert.sol";
import "../interfaces/IMasterPenpie.sol";
import "../interfaces/ILocker.sol";

/// @title Smart Pendle Convertor
/// @author Magpie Team

contract SmartPendleConvert is
    ISmartPendleConvert,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public mPendleOFT;
    address public mPendleConvertor;
    address public pendle;
    address public router;
    address public pendleMPendlePool;
    address public masterPenpie;
    address public pendleAsset;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public WAD = 1e18;
    uint256 public ratio;
    uint256 public buybackThreshold;
    ILocker public mPendleSV;

    /* ===== 1st upgrade ===== */
    uint256 constant Pendle_Index = 0;
    uint256 constant MPendle_Index = 1;

    /* ============ Errors ============ */

    error IncorrectRatio();
    error MinRecNotMatch();
    error MustNoBeZero();
    error IncorrectThreshold();
    error AddressZero();

    /* ============ Events ============ */

    event mPendleConverted(
        address user,
        uint256 depositedPendle,
        uint256 obtainedmPendle,
        uint256 mode
    );

    event mPendleSVUpdated(address _oldmPendleSV, address _newmPendleSV);
    event PancakeSwapRouterSet(address _router, address _pendleMPendlePool);

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __SmartPendleConvert_init(
        address _mPendleOFT,
        address _mPendleConvertor,
        address _pendle,
        address _router,
        address _pendleMPendlePool,
        address _masterPenpie,
        address _pendleAsset,
        uint256 _ratio
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        mPendleOFT = _mPendleOFT;
        mPendleConvertor = _mPendleConvertor;
        pendle = _pendle;
        router = _router;
        pendleMPendlePool = _pendleMPendlePool;
        masterPenpie = _masterPenpie;
        pendleAsset = _pendleAsset;
        ratio = _ratio;
        buybackThreshold = 9000;
    }

    /* ============ External Getters ============ */

    function estimateTotalConversion(
        uint256 _amount,
        uint256 _convertRatio
    ) external view returns (uint256 minimumEstimatedTotal) {
        if (_convertRatio > DENOMINATOR) revert IncorrectRatio();

        uint256 buybackAmount = _amount -
            ((_amount * _convertRatio) / DENOMINATOR);
        uint256 convertAmount = _amount - buybackAmount;
        uint256 amountOut = 0;

        if (buybackAmount > 0) {
            (amountOut) = IPancakeStableSwapTwoPool(pendleMPendlePool).get_dy(Pendle_Index, MPendle_Index, buybackAmount);
        }

        return (amountOut + convertAmount);
    }

    function maxSwapAmount() public view returns (uint256) {
        uint256 pendleBalance = IPancakeStableSwapTwoPool(pendleMPendlePool).balances(Pendle_Index);
        uint256 mPendleBalance = IPancakeStableSwapTwoPool(pendleMPendlePool).balances(MPendle_Index);

        if (pendleBalance >= mPendleBalance) return 0;

        return ((mPendleBalance - pendleBalance) * ratio) / DENOMINATOR;
    }

    function currentRatio() public view returns (uint256) {
        uint256 amountOut = IPancakeStableSwapTwoPool(pendleMPendlePool).get_dy(MPendle_Index, Pendle_Index, 1e18);
        return (amountOut * DENOMINATOR) / 1e18;
    }

    /* ============ External Functions ============ */

    function convert(
        uint256 _amountIn,
        uint256 _convertRatio,
        uint256 _minRec,
        uint256 _mode
    ) external nonReentrant returns (uint256 obtainedMPendleAmount) {
        obtainedMPendleAmount = _convertFor(
            _amountIn,
            _convertRatio,
            _minRec,
            msg.sender,
            _mode
        );
    }

    function convertFor(
        uint256 _amountIn,
        uint256 _convertRatio,
        uint256 _minRec,
        address _for,
        uint256 _mode
    ) external nonReentrant returns (uint256 obtainedMPendleAmount) {
        obtainedMPendleAmount = _convertFor(
            _amountIn,
            _convertRatio,
            _minRec,
            _for,
            _mode
        );
    }

    // should mainly used by pendle staking upon sending pendle
    function smartConvert(
        uint256 _amountIn,
        uint256 _mode
    ) external override nonReentrant returns (uint256 obtainedMPendleAmount) {
        if (_amountIn == 0) revert MustNoBeZero();

        uint256 convertRatio = _calConvertRatio(_amountIn);

        return
            _convertFor(_amountIn, convertRatio, _amountIn, msg.sender, _mode);
    }

    function smartConvertFor(uint256 _amountIn, uint256 _mode, address _for) external nonReentrant returns (uint256 obtainedmWomAmount) {
        if (_amountIn == 0) revert MustNoBeZero();

        uint256 convertRatio = _calConvertRatio(_amountIn);

        return _convertFor(_amountIn, convertRatio, _amountIn, _for, _mode);
    }

    function setRatio(uint256 _ratio) external onlyOwner {
        if (_ratio > DENOMINATOR) revert IncorrectRatio();

        ratio = _ratio;
    }

    function setBuybackThreshold(uint256 _threshold) external onlyOwner {
        if (_threshold > DENOMINATOR) revert IncorrectThreshold();

        buybackThreshold = _threshold;
    }

    /* ============ Admin Functions ============ */

    function setmPendleSV(address _newmPendleSV) public onlyOwner {
        if (_newmPendleSV == address(0)) revert AddressZero();

        address _oldmPendleSV = address(mPendleSV);
        mPendleSV = ILocker(_newmPendleSV);

        emit mPendleSVUpdated(_oldmPendleSV, _newmPendleSV);
    }

    function setPancakeSwapRouter(address _router, address _pendleMPendlePool) public onlyOwner {
        if (_router == address(0) || _pendleMPendlePool == address(0)) revert AddressZero();

        pendleMPendlePool = _pendleMPendlePool;
        router = _router;

        emit PancakeSwapRouterSet(_router, _pendleMPendlePool);
    }

    /* ============ Internal Functions ============ */

    function _calConvertRatio(uint256 _amountIn) internal view returns (uint256 convertRatio) {
        convertRatio = DENOMINATOR;
        uint256 mPendleToPendle = currentRatio();

        if (mPendleToPendle < buybackThreshold) {
            uint256 maxSwap = maxSwapAmount();
            uint256 amountToSwap = _amountIn > maxSwap ? maxSwap : _amountIn;
            uint256 convertAmount = _amountIn - amountToSwap;
            convertRatio = convertAmount * DENOMINATOR / _amountIn;
        }
    }

    function _convertFor(
        uint256 _amount,
        uint256 _convertRatio,
        uint256 _minRec,
        address _for,
        uint256 _mode
    ) internal returns (uint256 obtainedMPendleAmount) {
        if (_convertRatio > DENOMINATOR) revert IncorrectRatio();

        IERC20(pendle).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 buybackAmount = _amount -
            ((_amount * _convertRatio) / DENOMINATOR);
        uint256 convertAmount = _amount - buybackAmount;
        uint256 amountRec = 0;

        if (buybackAmount > 0) {
            address[] memory tokenPath = new address[](2);
            tokenPath[0] = pendle;
            tokenPath[1] = mPendleOFT;
            uint256[] memory flag = new uint256[](1);
            flag[0] = 2;

            IERC20(pendle).safeApprove(router, buybackAmount);

            uint256 oldBalance = IERC20(mPendleOFT).balanceOf(address(this));
            IStableSwapRouter(router).exactInputStableSwap(
                tokenPath,
                flag,
                buybackAmount,
                0,
                address(this)
            );
            uint256 newBalance = IERC20(mPendleOFT).balanceOf(address(this));

            amountRec = newBalance - oldBalance;
        }

        if (convertAmount > 0) {
            IERC20(pendle).safeApprove(mPendleConvertor, convertAmount);
            IConvertor(mPendleConvertor).convert(address(this), convertAmount, 0);
        }

        if (convertAmount + amountRec < _minRec) revert MinRecNotMatch();

        obtainedMPendleAmount = convertAmount + amountRec;

        if (_mode == 1) {
            IERC20(mPendleOFT).safeApprove(masterPenpie, obtainedMPendleAmount);
            IMasterPenpie(masterPenpie).depositFor(
                mPendleOFT,
                _for,
                obtainedMPendleAmount
            );
        } else if (_mode == 2) {
            IERC20(mPendleOFT).safeApprove(address(mPendleSV), obtainedMPendleAmount);
            mPendleSV.lockFor(obtainedMPendleAmount, _for);
        } else {
            IERC20(mPendleOFT).safeTransfer(_for, obtainedMPendleAmount);
        }

        emit mPendleConverted(_for, _amount, obtainedMPendleAmount, _mode);
    }
}
