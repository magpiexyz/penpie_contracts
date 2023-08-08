// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/wombat/IWombatRouter.sol";
import "../interfaces/IConvertor.sol";
import "../interfaces/wombat/IWombatAsset.sol";
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

    /* ============ Constructor ============ */

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
            address[] memory tokenPath = new address[](2);
            tokenPath[0] = pendle;
            tokenPath[1] = mPendleOFT;

            address[] memory poolPath = new address[](1);
            poolPath[0] = pendleMPendlePool;

            (amountOut, ) = IWombatRouter(router).getAmountOut(
                tokenPath,
                poolPath,
                int256(buybackAmount)
            );
        }

        return (amountOut + convertAmount);
    }

    function maxSwapAmount() public view returns (uint256) {
        uint256 pendleCash = IWombatAsset(pendleAsset).cash();
        uint256 pendleLiability = IWombatAsset(pendleAsset).liability();
        if (pendleCash >= pendleLiability) return 0;
       
        return ((pendleLiability - pendleCash) * ratio) / DENOMINATOR;
    }

    function currentRatio() public view returns (uint256) {
        address[] memory tokenPath = new address[](2);
        tokenPath[0] = mPendleOFT;
        tokenPath[1] = pendle;

        address[] memory poolPath = new address[](1);
        poolPath[0] = pendleMPendlePool;

        (uint256 amountOut, ) = IWombatRouter(router).getAmountOut(
            tokenPath,
            poolPath,
            1e18
        );
        return (amountOut * DENOMINATOR) / 1e18;
    }

    /* ============ External Functions ============ */

    function convert(
        uint256 _amountIn,
        uint256 _convertRatio,
        uint256 _minRec,
        uint256 _mode
    ) external returns (uint256 obtainedMPendleAmount) {
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
    ) external returns (uint256 obtainedMPendleAmount) {
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
    ) external override returns (uint256 obtainedMPendleAmount) {
        if (_amountIn == 0) revert MustNoBeZero();

        uint256 convertRatio = DENOMINATOR;
        uint256 mPendleToPendle = currentRatio();

        if (mPendleToPendle < buybackThreshold) {
            uint256 maxSwap = maxSwapAmount();
            uint256 amountToSwap = _amountIn > maxSwap ? maxSwap : _amountIn;
            uint256 convertAmount = _amountIn - amountToSwap;
            convertRatio = (convertAmount * DENOMINATOR) / _amountIn;
        }

        return
            _convertFor(_amountIn, convertRatio, _amountIn, msg.sender, _mode);
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

    /* ============ Internal Functions ============ */

    function _convertFor(
        uint256 _amount,
        uint256 _convertRatio,
        uint256 _minRec,
        address _for,
        uint256 _mode
    ) internal nonReentrant returns (uint256 obtainedMPendleAmount) {
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
            address[] memory poolPath = new address[](1);
            poolPath[0] = pendleMPendlePool;

            IERC20(pendle).safeApprove(router, buybackAmount);
            amountRec = IWombatRouter(router).swapExactTokensForTokens(
                tokenPath,
                poolPath,
                buybackAmount,
                0,
                address(this),
                block.timestamp
            );
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
