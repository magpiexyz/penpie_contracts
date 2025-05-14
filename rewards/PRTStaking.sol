// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMasterPenpie } from "../interfaces/IMasterPenpie.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

interface IERC20Burnable is IERC20 {
    function burn(address account, uint256 amount) external;
}

/// @title A contract for managing rewards for a pool
/// @author Magpie Team
/// @notice You can use this contract for getting informations about rewards for a specific pools
contract PRTStaking is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public PRT; // Penpie Recovery Token
    address public USDT; // usdt token

    uint256 public usdtPerPRTStored;
    uint256 public queuedUSDT;
    uint256 public totalPRTStaked; // to record all deposited PRT as PRT in this contract will be burnt upon USDT queued
    uint256 public totalPRTBurned; // to record all deposited PRT as PRT in this contract will be burnt upon USDT queued

    uint256 public PRTDecimal;

    struct UserInfo {
        uint256 USDTPerPRTPaid;
        uint256 entitledUSDT; // entitled USDT for the user, but claimable amount might be less as user can not claim USDT more than PRT he staked
        uint256 PRTStaked;
        uint256 USDTClaimed;
    }

    mapping(address => UserInfo) public userInfos;

    /* ============ Events ============ */

    event Staked(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount);
    event USDTPaid(address indexed _user, uint256 _amount, bool _debtCleaned);
    event USDTQueued(address indexed _queuer, uint256 _amount);
    event USDTReQueued(uint256 _amount);

    /* ============ Errors ============ */

    error NotAllowZeroAddress();
    error PRTBalanceNotEnough();
    error InconsistentDecimals();
    error MustForCleanDebt();
    error NotAllowZeroAmount();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __PRTStaking_init(address _penpieRecoveryToken, address _usdt) public initializer {
        if (_penpieRecoveryToken == address(0) || _usdt == address(0)) revert NotAllowZeroAddress();
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        PRT = _penpieRecoveryToken;
        USDT = _usdt;

        PRTDecimal = IERC20Metadata(_penpieRecoveryToken).decimals();
        uint256 USDTDecimal = IERC20Metadata(_usdt).decimals();

        if (PRTDecimal != USDTDecimal) revert InconsistentDecimals();
    }

    /* ============ External Getters ============ */

    /// amount of USDT token claimable by a user. A user's claimable amount is capped at user's staked PRT.
    ///                 a bool flag if this claim resulting in fully clean a user's debt
    function claimableUSDT(
        address _account
    ) public view returns (uint256 claimable, uint256 entitledUSDT, bool debtCleaned) {
        entitledUSDT = _entitledUSDT(_account);

        UserInfo storage user = userInfos[_account];

        // a user can not claim more than what his PRT staked

        if (entitledUSDT >= user.PRTStaked) {
            claimable = user.PRTStaked;
            debtCleaned = true;
        } else {
            claimable = entitledUSDT;
            debtCleaned = false;
        }
    }

    /// @notice Returns amount of USDT token entitled by a user
    /// @param _account Address account
    /// @return Returns amount of USDT token entitled by a user. User's entitled USDT amount for his PRT staking, but might be
    ///                 greater than claimable as this is not considering a user's USDT claim capped at his PRT stake amount.
    function entitledUSDT(address _account) public view returns (uint256) {
        return _entitledUSDT(_account);
    }

    function withdrawable(address _account) public view returns (uint256) {
        UserInfo storage user = userInfos[_account];
        (uint256 claimableAmount, , ) = claimableUSDT(_account);

        //Adjusting PRT on claimUsdt and withdraw PRT as well.
        return user.PRTStaked - claimableAmount;
    }

    function PRTBalance() public view returns (uint256) {
        return IERC20(PRT).balanceOf(address(this));
    }

    /* ============ External Functions ============ */

    function stake(uint256 _amount) external whenNotPaused nonReentrant {
        if (_amount == 0) revert NotAllowZeroAmount();

        _updateFor(msg.sender);
        UserInfo storage user = userInfos[msg.sender];

        user.PRTStaked += _amount;
        totalPRTStaked += _amount;

        IERC20(PRT).safeTransferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount);
    }

    // withdraw will incur claim compensated USDT at the same time.
    function withdraw(uint256 _amount) external whenNotPaused nonReentrant {
        if (_amount == 0) revert NotAllowZeroAmount();

        _claimUSDT(msg.sender, false); // must clean up claimable USDT for the user first, otherwise might resulting in less USDT claimed for user.
        UserInfo storage user = userInfos[msg.sender];

        if (_amount > user.PRTStaked) {
            revert PRTBalanceNotEnough();
        } else {
            totalPRTStaked -= _amount;
            user.PRTStaked -= _amount;
        }

        IERC20(PRT).safeTransfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }

    /// @notice Updates the reward information for one account
    /// @param _account Address account
    function updateFor(address _account) public nonReentrant whenNotPaused {
        _updateFor(_account);
    }

    function claimUSDT() public nonReentrant whenNotPaused {
        _claimUSDT(msg.sender, false);
    }

    // A permissionless clean up debt function so that USDT can be reququed
    function claimAndClean(address _account) external nonReentrant whenNotPaused {
        _claimUSDT(_account, true);
    }

    /// @notice Sends new usdt to be distributed to the PRT staking.
    /// @param _amount Amount of USDT to be distributed
    function queueUSDT(uint256 _amount) external whenNotPaused nonReentrant {
        if (_amount == 0) revert NotAllowZeroAmount();

        IERC20(USDT).safeTransferFrom(msg.sender, address(this), _amount);

        if (totalPRTStaked == 0) {
            queuedUSDT += _amount;
        } else {
            if (queuedUSDT > 0) {
                _amount += queuedUSDT;
                queuedUSDT = 0;
            }

            uint256 prtLeft = PRTBalance();
            if (prtLeft >= _amount) {
                totalPRTBurned += _amount;
                usdtPerPRTStored += (_amount * 10 ** PRTDecimal) / totalPRTStaked;
                IERC20Burnable(PRT).burn(address(this), _amount);
            } else {
                totalPRTBurned += prtLeft;
                queuedUSDT += _amount - prtLeft;
                usdtPerPRTStored += (prtLeft * 10 ** PRTDecimal) / totalPRTStaked;
                IERC20Burnable(PRT).burn(address(this), prtLeft);
            }

            emit USDTQueued(msg.sender, _amount);
        }
    }

    /* ============ Internal Functions ============ */

    function _claimUSDT(address _account, bool _mustForClean) private {
        _updateFor(_account);

        (uint256 claimableAmount, uint256 entitledAmount, bool debtAllClean) = claimableUSDT(
            _account
        );

        if (_mustForClean && !debtAllClean) revert MustForCleanDebt();

        UserInfo storage userInfo = userInfos[_account];

        if (debtAllClean) {
            _cleanUpPosition(userInfo, entitledAmount, claimableAmount);
        } else {
            totalPRTStaked -= claimableAmount;
            userInfo.PRTStaked -= claimableAmount;
        }

        userInfo.USDTClaimed += claimableAmount;
        userInfo.entitledUSDT = 0;

        IERC20(USDT).safeTransfer(_account, claimableAmount);

        emit USDTPaid(_account, claimableAmount, debtAllClean);
    }

    function _cleanUpPosition(
        UserInfo storage userInfo,
        uint256 _entitledUSDTAmount,
        uint256 _claimableUSDTAmount
    ) internal {
        // clean up user's PRT staked accounting as all debt paid
        totalPRTStaked -= userInfo.PRTStaked;
        userInfo.PRTStaked = 0;

        // need to re queue extra USDT
        uint256 USDTToRedistribute = _entitledUSDTAmount - _claimableUSDTAmount;
        queuedUSDT += USDTToRedistribute;

        emit USDTReQueued(queuedUSDT);
    }

    function _entitledUSDT(address _account) internal view returns (uint256) {
        UserInfo storage userInfo = userInfos[_account];

        return
            ((userInfo.PRTStaked * (usdtPerPRTStored - userInfo.USDTPerPRTPaid)) /
                10 ** PRTDecimal) + userInfo.entitledUSDT;
    }

    function _updateFor(address _account) internal {
        UserInfo storage userInfo = userInfos[_account];
        if (userInfo.USDTPerPRTPaid == usdtPerPRTStored) return;

        userInfo.entitledUSDT = _entitledUSDT(_account);
        userInfo.USDTPerPRTPaid = usdtPerPRTStored;
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
