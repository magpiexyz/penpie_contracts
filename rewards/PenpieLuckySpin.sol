// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import { VRFCoordinatorV2Interface } from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import { VRFConsumerBaseV2Upgradeable } from "../libraries/VRFConsumerBaseV2Upgradeable.sol";

import { IConvertor } from "../interfaces/IConvertor.sol";
import { ILocker } from "../interfaces/ILocker.sol";

contract PenpieLuckySpin is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VRFConsumerBaseV2Upgradeable
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ============ Structs ============ */

    struct UserReward {
        uint256 amount;
        address token;
    }

    struct UserSpinInfo {
        uint256 requestID;
        uint256 requestResult;
        uint256 inputAmount;
        uint256 vault;
        uint256 spinTime;
        bool waitingClaim;
        bool waitingVRF;
        UserReward userReward;
    }

    struct SpinReward {
        address token;
        uint256 baseRate;
        uint256 probWeight;
    }

    struct Threshold {
        uint256 upperBound;
        uint256 value;
    }

    /* ============ State Variables ============ */

    uint256 public constant DENOMINATOR = 10000;

    // VRF settings
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant CALLBACK_GAS_LIMIT = 600000;
    uint32 public constant NUM_WORDS = 1;

    VRFCoordinatorV2Interface private COORDINATOR;
    bytes32 private keyHash;
    uint64 private subscriptionId;

    // converter sittings
    IConvertor public converter;
    uint256 public convertMode;

    // spin settings
    IERC20 public inputToken;
    uint256 public minInput;
    uint256 public maxInput;
    uint256 public expiredSecond;
    IERC20 public prtToken;

    // reward settings
    uint256 public totalRewardWeight;
    uint256 public rewardsCount;
    Threshold[] public thresholds;

    mapping(address => UserSpinInfo) public userSpinInfos;
    mapping(uint256 => SpinReward) public spinRewards;
    mapping(uint256 => address) public userRequests;

    /* ============ Events ============ */

    event ReceivedRandomNumber(address indexed _user, uint256 requestID, uint256 _num);
    event UserSpinned(address indexed _user, uint256 _inputAmount, uint256 requestID);
    event RewardsClaimed(address indexed _user, uint256 indexed requestID, address _token, uint256 _rewardAmount, uint256 _inputAmount);
    event RewardAdded(address indexed _token, uint256 _baseRate, uint256 _probWeight);
    event RewardUpdated(
        uint256 indexed _index,
        address indexed _token,
        uint256 _baseRate,
        uint256 _probWeight
    );
    event RewardRemoved(
        uint256 indexed _index,
        address indexed _token,
        uint256 _baseRate,
        uint256 _probWeight
    );
    event ThresholdsSet(Threshold[] _thresholds);
    event coordinatorUpdated(address indexed _oldCoordinator, address indexed _newCoordinator);
    event keyHashUpdated(bytes32 _oldKeyHash, bytes32 _newKeyHash);
    event subscriptionIdUpdated(uint64 _oldSubscriptionId, uint64 _newSubscriptionId);
    event convertModeUpdated(uint256 _oldConvertMode, uint256 _newConvertMode);
    event inputTokenUpdated(address _oldInputToken, address _newInputToken);
    event inputSettingUpdated(
        uint256 _oldMinInput,
        uint256 _oldMaxInput,
        uint256 _newMinInput,
        uint256 _newMaxInput
    );

    /* ============ Errors ============ */

    error IncorrectInput();
    error OnlyCoordinator();
    error WaitToClaim();
    error OutOfRange();
    error UnderSpinning();
    error NothingToClaim();
    error RewardExpired();
    error IncorrectRewardWeight();
    error RewardInitilized();
    error InvalidInputLength();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __LuckySpin_init(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address _converter,
        uint256 _convertMode,
        address _inputToken,
        uint256 _minInput,
        uint256 _maxInput,
        uint256 _expiredSecond,
        address _prtToken
    ) public initializer {
        __Ownable_init();
        __VRFConsumerBaseV2Upgradeable_init(_vrfCoordinator);
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        converter = IConvertor(_converter);
        convertMode = _convertMode;
        inputToken = IERC20(_inputToken);
        minInput = _minInput;
        maxInput = _maxInput;
        expiredSecond = _expiredSecond;
        prtToken = IERC20(_prtToken);
        totalRewardWeight = 0;
        _pause(); // Pause the contract once it has been initialized because the reward is not set yet
    }

    /* ============ Modifiers ============ */

    modifier _onlyCoordinator() {
        if (msg.sender != address(COORDINATOR)) revert OnlyCoordinator();
        _;
    }

    /* ============ External Getters ============ */

    /// @dev if the status is not 0, it means there are rewards waiting for the user to claim.
    function unclaimReward(address user) external view returns (uint256 rewardAmount) {
        UserSpinInfo storage userInfo = userSpinInfos[user];

        if (userInfo.waitingClaim && block.timestamp <= userInfo.spinTime + expiredSecond) {
            SpinReward memory spinReward = spinRewards[userInfo.requestResult];
            rewardAmount =
                (userInfo.inputAmount * spinReward.baseRate * _getMultiplier(userInfo.vault)) /
                DENOMINATOR ** 2;
        } else {
            rewardAmount = 0;
        }
    }

    function getExpectBoost(address _user) external view returns (uint256 value) {
        uint256 vault = prtToken.balanceOf(_user);
        for (uint256 i = 0; i < thresholds.length; i++) {
            if (vault < thresholds[i].upperBound) {
                return thresholds[i].value;
            }
        }
    }

    /* ============ External Functions ============ */

    function spinTheWheel(
        uint256 _inputAmount
    ) external whenNotPaused nonReentrant returns (uint256 requestID) {
        if (_inputAmount < minInput || _inputAmount > maxInput) revert IncorrectInput();

        requestID = _spin(_inputAmount);

        emit UserSpinned(msg.sender, _inputAmount, requestID);
    }

    function getRewards() external nonReentrant {
        UserSpinInfo storage userInfo = userSpinInfos[msg.sender];
        if (!userInfo.waitingClaim) revert NothingToClaim();
        if (userInfo.waitingVRF) revert UnderSpinning();
        if (expiredSecond > 0 && userInfo.spinTime + expiredSecond < block.timestamp)
            revert RewardExpired();

        SpinReward memory spinReward = spinRewards[userInfo.requestResult];
        uint256 rewardAmount = this.unclaimReward(msg.sender);
        userInfo.userReward.token = spinReward.token;
        userInfo.userReward.amount = rewardAmount;

        IERC20(userInfo.userReward.token).safeTransfer(msg.sender, userInfo.userReward.amount);

        userInfo.waitingClaim = false;

        emit RewardsClaimed(msg.sender, userInfo.requestID, userInfo.userReward.token, userInfo.userReward.amount, userInfo.inputAmount);
    }

    function getThresholds() external view returns (Threshold[] memory) {
        return thresholds;
    }

    function getSpinRewards() external view returns (SpinReward[] memory) {
        SpinReward[] memory rewards = new SpinReward[](rewardsCount);
        for (uint256 i = 0; i < rewardsCount; i++) {
            rewards[i] = spinRewards[i];
        }
        return rewards;
    }

    /* ============ Internal Functions ============ */

    function _spin(uint256 _inputAmount) internal returns (uint256 requestID) {
        UserSpinInfo storage userInfo = userSpinInfos[msg.sender];
        if (userInfo.waitingClaim && userInfo.spinTime + expiredSecond >= block.timestamp)
            revert WaitToClaim();

        // Get user's total staked mPendle amount
        uint256 vault = prtToken.balanceOf(msg.sender);

        // Transfer the Pendle tokens to this contract
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), _inputAmount);

        uint256 amtToDirectConvert = _inputAmount / 2;
        uint256 amtToSmartConvert = _inputAmount - amtToDirectConvert; // Do this to prevent the dust

        // Convert a half of input token to mToken directly
        IERC20(inputToken).safeIncreaseAllowance(converter.mPendleConvertor(), amtToDirectConvert);
        IConvertor(converter.mPendleConvertor()).convert(
            msg.sender,
            amtToDirectConvert,
            convertMode
        );

        // Convert the input token and lock it if need
        IERC20(inputToken).safeIncreaseAllowance(address(converter), amtToSmartConvert);
        converter.smartConvertFor(amtToSmartConvert, convertMode, msg.sender);

        requestID = _requestRandomWords(); // Request VRF

        userInfo.waitingClaim = true;
        userInfo.waitingVRF = true;
        userInfo.requestID = requestID;
        userInfo.inputAmount = _inputAmount;
        userInfo.vault = vault;
        userInfo.spinTime = block.timestamp;
        userRequests[requestID] = msg.sender;
    }

    function _requestRandomWords() internal returns (uint256 requestID) {
        requestID = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );
    }

    function _pickRandomReward(uint256 randomNumber) internal view returns (uint256 reward) {
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < rewardsCount; i++) {
            totalWeight += spinRewards[i].probWeight;
        }
        uint256 shootingNumber = randomNumber % totalWeight;
        uint256 accumulatedWeight = 0;
        for (uint256 i = 0; i < rewardsCount; i++) {
            accumulatedWeight += spinRewards[i].probWeight;
            if (shootingNumber < accumulatedWeight) {
                return i;
            }
        }
    }

    function _getMultiplier(uint256 input) internal view returns (uint256 value) {
        for (uint256 i = 0; i < thresholds.length; i++) {
            if (input < thresholds[i].upperBound) {
                return thresholds[i].value;
            }
        }
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory randomWords
    ) internal override _onlyCoordinator {
        address userAddress = userRequests[_requestId];
        UserSpinInfo storage userInfo = userSpinInfos[userAddress];
        userInfo.waitingVRF = false;
        userInfo.requestResult = _pickRandomReward(randomWords[0]);

        emit ReceivedRandomNumber(userAddress, _requestId, userInfo.requestResult);
    }

    /* ============ Admin Functions ============ */

    function pause() external nonReentrant onlyOwner {
        _pause();
    }

    function unpause() external nonReentrant onlyOwner {
        if (totalRewardWeight != DENOMINATOR) revert IncorrectRewardWeight();
        _unpause();
    }

    function initRewards(
        address[] calldata _tokens,
        uint256[] calldata _baseRates,
        uint256[] calldata _probWeights,
        Threshold[] memory _thresholds
    ) external onlyOwner whenPaused {
        require(
            _tokens.length == _baseRates.length && _tokens.length == _probWeights.length,
            "Only can be called when the reward"
        );
        if (totalRewardWeight != 0 || thresholds.length != 0) revert RewardInitilized();

        if (_tokens.length != _baseRates.length || _tokens.length != _probWeights.length)
            revert InvalidInputLength();

        for (uint256 i = 0; i < _tokens.length; i++) {
            addReward(_tokens[i], _baseRates[i], _probWeights[i]);
        }

        if (totalRewardWeight != DENOMINATOR) revert IncorrectRewardWeight();

        setThresholds(_thresholds);
        _unpause();
    }

    function addReward(
        address _token,
        uint256 _baseRate,
        uint256 _probWeight
    ) public onlyOwner whenPaused {
        spinRewards[rewardsCount] = SpinReward(_token, _baseRate, _probWeight);
        rewardsCount++;
        totalRewardWeight += _probWeight;
        if (totalRewardWeight > DENOMINATOR) revert IncorrectRewardWeight();

        emit RewardAdded(_token, _baseRate, _probWeight);
    }

    function updateReward(
        uint256 _index,
        uint256 newBaseRate,
        uint256 newProbWeight
    ) external onlyOwner whenPaused {
        if (_index >= rewardsCount) revert OutOfRange();

        SpinReward storage reward = spinRewards[_index];

        totalRewardWeight -= reward.probWeight;

        reward.baseRate = newBaseRate;
        reward.probWeight = newProbWeight;

        totalRewardWeight += newProbWeight;

        if (totalRewardWeight != DENOMINATOR) revert IncorrectRewardWeight();

        emit RewardUpdated(_index, reward.token, newBaseRate, newProbWeight);
    }

    function removeReward(uint256 _index) external onlyOwner whenPaused {
        if (_index >= rewardsCount) revert OutOfRange();

        if (_index < rewardsCount - 1) {
            spinRewards[_index] = spinRewards[rewardsCount - 1];
        }
        totalRewardWeight -= spinRewards[_index].probWeight;
        address removedRewardToken = spinRewards[rewardsCount - 1].token;
        uint256 removedRewardBaseRate = spinRewards[rewardsCount - 1].baseRate;
        uint256 removedRewardProbWeight = spinRewards[rewardsCount - 1].probWeight;
        delete spinRewards[rewardsCount - 1];
        rewardsCount--;

        emit RewardRemoved(
            _index,
            removedRewardToken,
            removedRewardBaseRate,
            removedRewardProbWeight
        );
    }

    function setThresholds(Threshold[] memory _thresholds) public onlyOwner whenPaused {
        for (uint i = 0; i < _thresholds.length; i++) {
            bool found = false;
            for (uint j = 0; j < thresholds.length; j++) {
                if (_thresholds[i].upperBound == thresholds[j].upperBound) {
                    thresholds[j] = _thresholds[i];
                    found = true;
                    break;
                }
            }
            if (!found) {
                thresholds.push(_thresholds[i]);
            }
        }

        emit ThresholdsSet(_thresholds);
    }

    function updateCoordinatorSetting(
        address newCoordinator,
        bytes32 newKeyHash,
        uint64 newSubscriptionId
    ) external onlyOwner whenPaused {
        if (address(COORDINATOR) != newCoordinator) {
            address oldCoordinator = address(COORDINATOR);
            COORDINATOR = VRFCoordinatorV2Interface(newCoordinator);
            emit coordinatorUpdated(oldCoordinator, newCoordinator);
        }

        if (keyHash != newKeyHash) {
            bytes32 oldKeyHash = keyHash;
            keyHash = newKeyHash;
            emit keyHashUpdated(oldKeyHash, newKeyHash);
        }

        if (subscriptionId != newSubscriptionId) {
            uint64 oldSubscriptionId = subscriptionId;
            subscriptionId = newSubscriptionId;
            emit subscriptionIdUpdated(oldSubscriptionId, newSubscriptionId);
        }
    }

    function setConvertMode(uint256 newConvertMode) external onlyOwner whenPaused {
        uint256 oldConvertMode = convertMode;
        convertMode = newConvertMode;
        emit convertModeUpdated(oldConvertMode, newConvertMode);
    }

    function setInput(
        address _inputToken,
        uint256 _minInput,
        uint256 _maxInput
    ) external onlyOwner {
        address oldInputToken = address(inputToken);
        uint256 oldMin = minInput;
        uint256 oldMax = maxInput;

        inputToken = IERC20(_inputToken);
        minInput = _minInput;
        maxInput = _maxInput;

        emit inputTokenUpdated(oldInputToken, _inputToken);
        emit inputSettingUpdated(oldMin, oldMax, _minInput, _maxInput);
    }
}
