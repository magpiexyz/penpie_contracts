// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./interfaces/IMintableERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UtilLib } from "./libraries/UtilLib.sol";
import { batchSwapHelper } from "./libraries/batchSwapHelper.sol";

/// @title BuyBackBurnProvider
/// @author Magpie Team
/// @notice This contract is the main contract that owner will intreact with in order swap a particular token with another token so as to burn it and increase the peg.

contract BuyBackBurnProvider is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    struct ScheduleData {
        uint256 swappedAmount;
        bytes32 aggregator;
        address fromToken;
        address toToken;
        address receiver;
        bool isActive;
        bool isDone;
        bool isOnchain;
    }

    struct Schedule {
        uint256 scheduleId;
        uint256 totalFromTokenAmount;
        uint256 fromTokenUsed;
        uint256 buybackTimes;
        uint256 buybackInterval;
        uint256 lastExecuted;
        uint256 lastUpdated;
        uint256 executedCount;
        ScheduleData data;
    }

    /* ============ State Variables ============ */
    bytes32 public constant BOTROLE = keccak256("BOTROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    address public odosRouter;

    mapping(bytes32 => bool) public supportedAggregator;
    Schedule[] public schedules;

    /* ============ Events ============ */

    event ScheduleAdded(uint256 indexed _scheduleIndex, address _fromToken, address _toToken, address _receiver, uint256 _totalFromTokenAmount, uint256 _buybackTimes, uint256 _buybackInterval, bytes32 _aggregator);
    event ScheduleUpdated(uint256 indexed _scheduleIndex, address _fromToken, address _toToken, address _receiver, uint256 _totalFromTokenAmount, uint256 _fromTokenUsed, uint256 _buybackTimes, uint256 _buybackInterval, uint256 _lastExecuted, uint256 _executedCount);
    event ScheduleStateChanged(uint256 indexed _scheduleIndex, bool _isActive);
    event BuybackExecuted(uint256 indexed _scheduleIndex, uint256 _inAmount, uint256 _outAmount, bytes32 _aggregator);
    event AggregatorSet(string indexed aggregator, bool status);

    /* ============ Errors ============ */

    error InsufficientTokenInBalance();
    error OnlyActiveSchedule();
    error TransactionDataLengthMismatch();
    error OnlyAfterInterval();
    error ScheduleEnded();
    error InvalidAddress();
    error InvalidParams();
    error OnlyOnchainSchedule();
    error OnlyOffchainSchedule();
    error InvalidAggregator();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __BuyBackBurnProvider_init(
        address _odosRouter,
        address _admin
    ) public initializer {
        UtilLib.checkNonZeroAddress(_admin);

        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        odosRouter = _odosRouter;
    }

    /* ============ External Functions ============ */

    function genericSwap(bytes calldata _transactionData, address _tokenIn, uint256 _amountIn, address _tokenOut, address _receiver) external whenNotPaused nonReentrant returns (uint256) {
        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        uint256 swappedAmount = batchSwapHelper.swap(_transactionData, _tokenIn, _amountIn, _tokenOut, _receiver, odosRouter);
        return swappedAmount;
    }

    function getSchedule(uint256 _index) public view returns (Schedule memory) {
        return schedules[_index];
    }

    function getScheduleLength() public view returns (uint256) {
        return schedules.length;
    }

    function getActiveSchedules() external view returns (Schedule[] memory) {
        uint256 count = 0;

        // Count active schedules
        for (uint256 i = 0; i < schedules.length; i++) {
            if (schedules[i].data.isActive && !schedules[i].data.isDone) {
                count++;
            }
        }

        // Create array for active schedules
        Schedule[] memory activeSchedules = new Schedule[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            if (schedules[i].data.isActive && !schedules[i].data.isDone) {
                activeSchedules[index] = schedules[i];
                index++;
            }
        }

        return activeSchedules;
    }

    function getInactiveSchedules() external view returns (Schedule[] memory) {
        uint256 count = 0;

        // Count inactive schedules
        for (uint256 i = 0; i < schedules.length; i++) {
            if (!schedules[i].data.isActive) {
                count++;
            }
        }

        // Create array for inactive schedules
        Schedule[] memory inactiveSchedules = new Schedule[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            if (!schedules[i].data.isActive) {
                inactiveSchedules[index] = schedules[i];
                index++;
            }
        }

        return inactiveSchedules;
    }

    function getCompletedSchedules() external view returns (Schedule[] memory) {
        uint256 count = 0;

        // Count completed schedules
        for (uint256 i = 0; i < schedules.length; i++) {
            if (schedules[i].data.isDone && schedules[i].data.isActive) {
                count++;
            }
        }

        // Create array for completed schedules
        Schedule[] memory completedSchedules = new Schedule[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            if (schedules[i].data.isDone && schedules[i].data.isActive) {
                completedSchedules[index] = schedules[i];
                index++;
            }
        }

        return completedSchedules;
    }

    /* ============ BotRole Functions ============ */

    function executeBuyback(bytes calldata _transactionData, uint256 _scheduleIndex) external whenNotPaused nonReentrant onlyRole(BOTROLE) returns (uint256) {
        Schedule storage schedule = schedules[_scheduleIndex];
        
        if (!schedule.data.isOnchain) revert OnlyOnchainSchedule();
        if (!schedule.data.isActive) revert OnlyActiveSchedule();
        if (schedule.data.isDone) revert ScheduleEnded();
        if (block.timestamp < schedule.lastExecuted + schedule.buybackInterval * 1 hours) revert OnlyAfterInterval();

        uint256 swapAmount = schedule.totalFromTokenAmount / schedule.buybackTimes;

        uint256 tokenInBalance = IERC20(schedule.data.fromToken).balanceOf(address(this));
        if (tokenInBalance < swapAmount) revert InsufficientTokenInBalance();

        uint256 swappedAmount = batchSwapHelper.swap(_transactionData, schedule.data.fromToken, swapAmount, schedule.data.toToken, schedule.data.receiver, odosRouter);

        schedule.fromTokenUsed += swapAmount;
        schedule.executedCount += 1;
        schedule.data.isDone = schedule.executedCount == schedule.buybackTimes;
        schedule.lastExecuted = block.timestamp;
        schedule.data.swappedAmount += swappedAmount;

        emit BuybackExecuted(_scheduleIndex, swapAmount, swappedAmount, keccak256("ODOS"));
        return swappedAmount;
    }

    function executeBuybackOffChain(uint256 _scheduleIndex, uint256 _swapAmount, uint256 _swappedAmount) external whenNotPaused nonReentrant onlyRole(BOTROLE) {
        Schedule storage schedule = schedules[_scheduleIndex];
        if (schedule.data.isOnchain) revert OnlyOffchainSchedule();
        if (!schedule.data.isActive) revert OnlyActiveSchedule();
        if (schedule.data.isDone) revert ScheduleEnded();

        schedule.fromTokenUsed += _swapAmount;
        schedule.executedCount += 1;
        schedule.data.isDone = schedule.executedCount == schedule.buybackTimes;
        schedule.lastExecuted = block.timestamp;
        schedule.data.swappedAmount += _swappedAmount;

        emit BuybackExecuted(_scheduleIndex, _swapAmount, _swappedAmount, schedule.data.aggregator);
    }

    /* ============ OperatorRole Functions ============ */

    function addSchedule(address _fromToken, address _toToken, address _receiver, uint256 _totalFromTokenAmount, uint256 _buybackTimes, uint256 _buybackInterval, bool _isOnchain, bytes32 _aggregator) external onlyRole(OPERATOR_ROLE) {
        if (_fromToken == address(0) || _toToken == address(0) || _receiver == address(0))
            revert InvalidAddress();
        if (_totalFromTokenAmount == 0 || _buybackTimes == 0 || _buybackInterval == 0)
            revert InvalidParams();
        if (!supportedAggregator[_aggregator])
            revert InvalidAggregator();

        ScheduleData memory data = ScheduleData({
            aggregator: _aggregator,
            swappedAmount: 0,
            fromToken: _fromToken,
            toToken: _toToken,
            receiver: _receiver,
            isActive: true,
            isDone: false,
            isOnchain: _isOnchain
        });

        schedules.push(
            Schedule({
                scheduleId: schedules.length,
                totalFromTokenAmount: _totalFromTokenAmount,
                fromTokenUsed: 0,
                buybackTimes: _buybackTimes,
                buybackInterval: _buybackInterval,
                lastExecuted: 0,
                lastUpdated: block.timestamp,
                executedCount: 0,
                data: data
            })
        );

        emit ScheduleAdded(schedules.length - 1, _fromToken, _toToken, _receiver, _totalFromTokenAmount, _buybackTimes, _buybackInterval, _aggregator);
    }

    function updateScheduleStatus(uint256 _scheduleIndex, bool _isActive) external onlyRole(OPERATOR_ROLE) {
        require(_scheduleIndex < schedules.length, "Invalid index");
        schedules[_scheduleIndex].data.isActive = _isActive;
        schedules[_scheduleIndex].lastUpdated = block.timestamp;

        emit ScheduleStateChanged(_scheduleIndex, _isActive);
    }

    function setSchedule(uint256 _scheduleIndex, address _fromToken, address _toToken, address _receiver, uint256 _totalFromTokenAmount, uint256 _fromTokenUsed, uint256 _buybackTimes, uint256 _buybackInterval, uint256 _lastExecuted, uint256 _executedCount) external onlyRole(OPERATOR_ROLE) {
        require(_scheduleIndex < schedules.length, "Invalid index");

        if (!schedules[_scheduleIndex].data.isActive) revert OnlyActiveSchedule();
        if (_fromToken == address(0) || _toToken == address(0) || _receiver == address(0))
            revert InvalidAddress();
        if (_totalFromTokenAmount == 0 || _buybackTimes == 0 || _buybackInterval == 0)
            revert InvalidParams();

        Schedule storage schedule = schedules[_scheduleIndex];
        schedule.data.fromToken = _fromToken;
        schedule.data.toToken = _toToken;
        schedule.data.receiver = _receiver;
        schedule.totalFromTokenAmount = _totalFromTokenAmount;
        schedule.fromTokenUsed = _fromTokenUsed;
        schedule.buybackTimes = _buybackTimes;
        schedule.buybackInterval = _buybackInterval;
        schedule.lastExecuted = _lastExecuted;
        schedule.executedCount = _executedCount;
        schedule.data.isDone = schedule.executedCount >= schedule.buybackTimes;
        schedule.data.swappedAmount = 0;
        schedule.lastUpdated = block.timestamp;

        emit ScheduleUpdated(_scheduleIndex, _fromToken, _toToken, _receiver, _totalFromTokenAmount, _fromTokenUsed, _buybackTimes, _buybackInterval, _lastExecuted, _executedCount);
    }

    function setSupportedAggregator(string calldata _aggregator, bool _isSupport) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(_aggregator).length > 0, "Empty aggregator name");
        bytes32 aggregatorHash = keccak256(abi.encodePacked(_aggregator));

        supportedAggregator[aggregatorHash] = _isSupport;
        emit AggregatorSet(_aggregator, _isSupport);
    }

    function pause() public onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(OPERATOR_ROLE) {
        _unpause();
    }
}
