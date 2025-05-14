// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

import "../interfaces/IPendleVoteManager.sol";
import "../libraries/math/Math.sol";

/// @title PenpieBribeManager
/// @notice Penpie bribe manager is used to manage market pools for voting and bribing.
///         This contract allows us to add and remove pools for Pendle market tokens.
///         When bribes are added, the tokens will be separated with a fee and transferred
///         to the distributor contract and the fee collector.
///         To save on gas fees, we will save all bribe tokens in each pool using a unique
///         index for pools and bribe tokens for each epoch (or round), instead of using nested mappings.
///         At the end of each epoch, we will retrieve the total bribes from this contract
///         and aggregate the voting results using subgraph querying.
///         We will calculate rewards for each user who has voted, package the distribution
///         using the merkleTree structure, and import it into the distributor contract.
///         This will allow users to claim their rewards from the distributor contract.
///
/// @author Penpie Team
contract PenpieBribeManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct Pool {
        address _market;
        bool _active;
        uint256 _chainId;
    }

    struct Bribe {
        address _token;
        uint256 _amount;
    }

    /* ============ State Variables ============ */

    address constant NATIVE = address(1);
    uint256 constant DENOMINATOR = 10000;

    address public voteManager;
    address payable public distributor;
    address payable private feeCollector;
    uint256 public feeRatio;
    uint256 public maxBribingBatch;

    uint256 public epochPeriod;
    uint256 public epochStartTime;
    uint256 private currentEpoch;

    Pool[] public pools;
    mapping(address => uint256) public marketToPid;
    mapping(address => uint256) public unCollectedFee;

    address[] public allowedTokens;
    mapping(address => bool) public allowedToken;
    mapping(bytes32 => Bribe) public bribes;  // The index is hashed based on the epoch, pid and token address
    mapping(bytes32 => bytes32[]) public bribesInPool;  // Mapping pool => bribes. The index is hashed based on the epoch, pid
    mapping(address => bool) public allowedOperator;

    /* ============ 1st upgrade for vePendle bribing ============ */

    address payable public distributorForVePendle;
    mapping(bytes32 => Bribe) public bribesForVePendle;
    mapping(bytes32 => bytes32[]) public bribesInPoolForVePendle;
    uint256 public pnpBribingRatio;

    /* ============ 2nd upgrade ============ */
    address public pendleMarketRegisterHelper;

    /* ============ Events ============ */

    event NewBribe(address indexed _user, uint256 indexed _epoch, uint256 _pid, address _bribeToken, uint256 _amount);
    event NewBribeForVePendle(address indexed _user, uint256 indexed _epoch, uint256 _pid, address _bribeToken, uint256 _amount);
    event NewPool(address indexed _market, uint256 _chainId);
    event EpochPushed(uint256 indexed _epoch, uint256 _startTime);
    event EpochForcePushed(uint256 indexed _epoch, uint256 _startTime);
    event UpdateOperatorStatus(address indexed _user, bool _status);
    event BribeReallocated(
        uint256 indexed _pid,
        address indexed _token,
        uint256 _epochFrom,
        uint256 _epochTo,
        uint256 _amount
    );
    event PendleMarketRegisterHelperSet(address _pendleMarketRegisterHelper);
    event UpdatePool(uint256 _pid, uint256 _chainId, address indexed _market, bool _isActive);
    event MarketPIDForceSet(address indexed _market, uint256 _pid);
    event EpochPeriodSet(uint256 _epochPeriod);
    event AllowedTokenAdded(address indexed _token);
    event AllowedTokenRemoved(address indexed _token);
    event DistributorSet(address indexed _distributor);
    event FeeCollectorSet(address indexed _collector);
    event FeeRatioSet(uint256 _feeRatio);
    event DistributorForVePendleSet(address indexed _distributorForVePendle);
    event PNPBribingRatioSet(uint256 _pnpBribingRatio);

    /* ============ Errors ============ */

    error InvalidPool();
    error InvalidBribeToken();
    error OnlyPoolRegisterHelper();
    error ZeroAddress();
    error ZeroAmount();
    error PoolOccupied();
    error InvalidEpoch();
    error OnlyNotInEpoch();
    error OnlyInEpoch();
    error InvalidTime();
    error InvalidBatch();
    error OnlyOperator();
    error MarketExists();
    error NativeTransferFailed();
    error InsufficientAmount();

    /* ============ Constructor ============ */

    constructor() { _disableInitializers(); }

    function __PenpieBribeManager_init(
        address _voteManager,
        uint256 _epochPeriod,
        uint256 _feeRatio
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        voteManager = _voteManager;
        epochPeriod = _epochPeriod;
        feeRatio = _feeRatio;
        maxBribingBatch = 8;
        currentEpoch = 0;
        allowedOperator[owner()] = true;
    }

    /* ============ Modifiers ============ */

    modifier onlyOperator() {
        if (!allowedOperator[msg.sender]) revert OnlyOperator();
        _;
    }    

    modifier _onlyPoolRegisterHelper() {
        if (msg.sender != pendleMarketRegisterHelper && msg.sender != owner()) revert OnlyPoolRegisterHelper();
        _;
    }

    /* ============ External Getters ============ */

    function exactCurrentEpoch() public view returns (uint256) {
        if (epochStartTime == 0) return 0;

        uint256 epochEndTime = epochStartTime + epochPeriod;
        if (block.timestamp > epochEndTime)
            return currentEpoch + 1;
        else
            return currentEpoch;
    }

    function getCurrentEpochEndTime() public view returns(uint256 endTime) {
        endTime = epochStartTime + epochPeriod;
    }

    function getApprovedTokens() public view returns(address[] memory) {
        return allowedTokens;
    }

    function getPoolLength() public view returns(uint256) {
        return pools.length;
    }

    /// @notice this function could make havey gas cost, please prevent to call this in non-view functions
    function getBribesInAllPools(uint256 _epoch) external view returns (Bribe[][] memory) {
        Bribe[][] memory rewards = new Bribe[][](pools.length);
        for (uint256 i = 0; i < pools.length; i++){
            rewards[i] = getBribesInPool(_epoch, i);
        }
        return rewards;
    }

    function getBribesInPool(uint256 _epoch, uint256 _pid) public view returns (Bribe[] memory) {
        if (_pid >= getPoolLength()) revert InvalidPool();
        
        bytes32 poolIdentifier = _getPoolIdentifier(_epoch, _pid);

        bytes32[] memory poolBribes = bribesInPool[poolIdentifier];
        Bribe[] memory rewards = new Bribe[](poolBribes.length);

        for (uint256 i = 0; i < poolBribes.length; i++) {
            rewards[i] = bribes[poolBribes[i]];
        }

        return rewards;
    }

    function getBribesInAllPoolsForVePendle(uint256 _epoch) external view returns (Bribe[][] memory) {
        Bribe[][] memory rewards = new Bribe[][](pools.length);
        for (uint256 i = 0; i < pools.length; i++){
            rewards[i] = getBribesInPoolForVePendle(_epoch, i);
        }
        return rewards;
    }

    function getBribesInPoolForVePendle(uint256 _epoch, uint256 _pid) public view returns (Bribe[] memory) {
        if (_pid >= getPoolLength()) revert InvalidPool();
        
        bytes32 poolIdentifier = _getPoolIdentifier(_epoch, _pid);

        bytes32[] memory poolBribes = bribesInPoolForVePendle[poolIdentifier];
        Bribe[] memory rewards = new Bribe[](poolBribes.length);

        for (uint256 i = 0; i < poolBribes.length; i++) {
            rewards[i] = bribesForVePendle[poolBribes[i]];
        }

        return rewards;
    }

    /* ============ External Functions ============ */

    function addBribeNative(uint256 _batch, uint256 _pid, bool _forPreviousEpoch) external payable nonReentrant whenNotPaused {
        _addBribeNative(_batch, _pid, _forPreviousEpoch, false);
    }

    function addBribeERC20(uint256 _batch, uint256 _pid, address _token, uint256 _amount, bool _forPreviousEpoch) external nonReentrant whenNotPaused {
        _addBribeERC20(_batch, _pid, _token, _amount, _forPreviousEpoch, false);
    }

    function addBribeNativeForVePendle(uint256 _batch, uint256 _pid, bool _forPreviousEpoch) external payable nonReentrant whenNotPaused {
        _addBribeNative(_batch, _pid, _forPreviousEpoch, true);
    }

    function addBribeERC20ForVePendle(uint256 _batch, uint256 _pid, address _token, uint256 _amount, bool _forPreviousEpoch) external nonReentrant whenNotPaused {
        _addBribeERC20(_batch, _pid, _token, _amount, _forPreviousEpoch, true);
    }

    function addBribeNativeToEpoch(uint256 _epoch, uint256 _pid, bool forVePendle) external payable nonReentrant whenNotPaused onlyOperator {
        if (_epoch < exactCurrentEpoch() - 1) revert InvalidEpoch();
        if (_pid >= pools.length || !pools[_pid]._active) revert InvalidPool();

        bool successNativeTransfer;
        uint256 bribeForVlPNP = msg.value;
        uint256 bribeForVePendle;
        uint256 totalFee = 0;

        if (forVePendle) {
            bribeForVlPNP = msg.value * pnpBribingRatio / DENOMINATOR;
            bribeForVePendle = msg.value - bribeForVlPNP;
            if (bribeForVePendle > 0) {
                (uint256 feeForVePendle, uint256 afterFeeForVePendle) = _addBribeForVePendle(_epoch, _pid, NATIVE, bribeForVePendle);
                totalFee += feeForVePendle;
                (successNativeTransfer, )  = distributorForVePendle.call{value: afterFeeForVePendle}("");
                if (!successNativeTransfer) revert NativeTransferFailed();
            }
        }

        (uint256 fee, uint256 afterFee) = _addBribe(_epoch, _pid, NATIVE, bribeForVlPNP);
        totalFee += fee;

        // transfer the token to the target directly in one time to save the gas fee
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[NATIVE] += totalFee;
            } else {
                feeCollector.call{value: totalFee}("");
            }
        }
        (successNativeTransfer, )  = distributor.call{value: afterFee}("");
        if (!successNativeTransfer) revert NativeTransferFailed();
    }

    function addBribeERC20ToEpoch(uint256 _epoch, uint256 _pid, address _token, uint256 _amount, bool forVePendle) external nonReentrant whenNotPaused onlyOperator {
        if (_epoch < exactCurrentEpoch() - 1) revert InvalidEpoch();
        if (_pid >= pools.length || !pools[_pid]._active) revert InvalidPool();
        if (!allowedToken[_token] || _token == NATIVE) revert InvalidBribeToken();

        uint256 bribeForVlPNP = _amount;
        uint256 bribeForVePendle;
        uint256 totalFee = 0;

        if (forVePendle) {
            bribeForVlPNP = _amount * pnpBribingRatio / DENOMINATOR;
            bribeForVePendle = _amount - bribeForVlPNP;
            if (bribeForVePendle > 0) {
                (uint256 feeForVePendle, uint256 afterFeeForVePendle) = _addBribeForVePendle(_epoch, _pid, _token, bribeForVePendle);
                totalFee += feeForVePendle;
                IERC20(_token).safeTransferFrom(msg.sender, distributorForVePendle, afterFeeForVePendle);
            }
        }

        (uint256 fee, uint256 afterFee) = _addBribe(_epoch, _pid, _token, bribeForVlPNP);
        totalFee += fee;

        // transfer the token to the target directly in one time to save the gas fee
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[_token] += totalFee;
                IERC20(_token).safeTransferFrom(msg.sender, address(this), totalFee);
            } else {
                IERC20(_token).safeTransferFrom(msg.sender, feeCollector, totalFee);
            }
        }
        
        IERC20(_token).safeTransferFrom(msg.sender, distributor, afterFee);
    }

    function pushEpoch(uint256 _time) external onlyOperator {
        epochStartTime = _time;
        currentEpoch ++;

        emit EpochPushed(currentEpoch, _time);
    }

    /* ============ Internal Functions ============ */

    function _getPoolIdentifier(uint256 _epoch, uint256 _pid) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(_epoch, _pid)
            );
    }

    function _getTokenIdentifier(uint256 _epoch, uint256 _pid, address _token) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(_epoch, _pid, _token)
            );
    }

    function _addBribeNative(uint256 _batch, uint256 _pid, bool _forPreviousEpoch, bool forVePendle) internal {
        if (_batch == 0 || _batch > maxBribingBatch) revert InvalidBatch();
        if (_pid >= pools.length || !pools[_pid]._active) revert InvalidPool();

        uint256 startFromEpoch = exactCurrentEpoch();
        if (startFromEpoch > 0 && _forPreviousEpoch){
            startFromEpoch -= 1;
        }
        uint256 totalFee = 0;
        uint256 totalBribing = 0;
        uint256 totalBribingForVePendle = 0;

        uint256 bribePerEpoch = msg.value / _batch;
        uint256 bribePerEpochForVlPNP = bribePerEpoch;
        uint256 bribePerEpochForVePendle = 0;
        if (forVePendle) {
            bribePerEpochForVlPNP = bribePerEpoch * pnpBribingRatio / DENOMINATOR;
            bribePerEpochForVePendle = bribePerEpoch - bribePerEpochForVlPNP;
        }

        for (uint256 epoch = startFromEpoch; epoch < startFromEpoch + _batch; epoch++) {
            if (bribePerEpochForVePendle > 0) {
                (uint256 feeForVePendle, uint256 afterFeeForVePendle) = _addBribeForVePendle(epoch, _pid, NATIVE, bribePerEpochForVePendle);
                totalFee += feeForVePendle;
                totalBribingForVePendle += afterFeeForVePendle;
            }
            (uint256 fee, uint256 afterFee) = _addBribe(epoch, _pid, NATIVE, bribePerEpochForVlPNP);
            totalFee += fee;
            totalBribing += afterFee;
        }

        // transfer the token to the target directly in one time to save the gas fee
        bool success;
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[NATIVE] += totalFee;
            } else {
                feeCollector.call{value: totalFee}("");
            }
        }
        (success, )  = distributor.call{value: totalBribing}("");
        if (!success) revert NativeTransferFailed();

        if (totalBribingForVePendle > 0) {
            (success, )  = distributorForVePendle.call{value: totalBribingForVePendle}("");
            if (!success) revert NativeTransferFailed();
        }
    }

    function _addBribeERC20(uint256 _batch, uint256 _pid, address _token, uint256 _amount, bool _forPreviousEpoch, bool forVePendle) internal {
        if (_batch == 0 || _batch > maxBribingBatch) revert InvalidBatch();
        if (_pid >= pools.length || !pools[_pid]._active) revert InvalidPool();
        if (!allowedToken[_token] || _token == NATIVE) revert InvalidBribeToken();

        uint256 startFromEpoch = exactCurrentEpoch();
        if (startFromEpoch > 0 && _forPreviousEpoch){
            startFromEpoch -= 1;
        }
        uint256 totalFee = 0;
        uint256 totalBribing = 0;
        uint256 totalBribingForVePendle = 0;

        uint256 bribePerEpochForVlPNP = _amount / _batch;
        uint256 bribePerEpochForVePendle = 0;
        if (forVePendle) {
            bribePerEpochForVlPNP = (_amount  * pnpBribingRatio) / (_batch * DENOMINATOR );
            bribePerEpochForVePendle = _amount / _batch - bribePerEpochForVlPNP;
        }

        for (uint256 epoch = startFromEpoch; epoch < startFromEpoch + _batch; epoch++) {
            if (bribePerEpochForVePendle > 0) {
                (uint256 feeForVePendle, uint256 afterFeeForVePendle) = _addBribeForVePendle(epoch, _pid, _token, bribePerEpochForVePendle);
                totalFee += feeForVePendle;
                totalBribingForVePendle += afterFeeForVePendle;
            }
            (uint256 fee, uint256 afterFee) = _addBribe(epoch, _pid, _token, bribePerEpochForVlPNP);
            totalFee += fee;
            totalBribing += afterFee;
        }

        // transfer the token to the target directly in one time to save the gas fee
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[_token] += totalFee;
                IERC20(_token).safeTransferFrom(msg.sender, address(this), totalFee);
            } else {
                IERC20(_token).safeTransferFrom(msg.sender, feeCollector, totalFee);
            }
        }
        
        IERC20(_token).safeTransferFrom(msg.sender, distributor, totalBribing);

        if (totalBribingForVePendle > 0) {
            IERC20(_token).safeTransferFrom(msg.sender, distributorForVePendle, totalBribingForVePendle);
        }
    }

    function _addBribe(uint256 _epoch, uint256 _pid, address _token, uint256 _amount) internal returns (uint256 fee, uint256 afterFee) {
        fee = _amount * feeRatio / DENOMINATOR;
        afterFee = _amount - fee;

        // We will generate a unique index for each pool and reward based on the epoch
        bytes32 poolIdentifier = _getPoolIdentifier(_epoch, _pid);
        bytes32 rewardIdentifier = _getTokenIdentifier(_epoch, _pid, _token);

        Bribe storage bribe = bribes[rewardIdentifier];
        bribe._amount += afterFee;
        if(bribe._token == address(0)) {
            bribe._token = _token;
            bribesInPool[poolIdentifier].push(rewardIdentifier);
        }

        emit NewBribe(msg.sender, _epoch, _pid, _token, afterFee);
    }

    function _addBribeForVePendle(uint256 _epoch, uint256 _pid, address _token, uint256 _amount) internal returns (uint256 fee, uint256 afterFee) {
        fee = _amount * feeRatio / DENOMINATOR;
        afterFee = _amount - fee;

        // We will generate a unique index for each pool and reward based on the epoch
        bytes32 poolIdentifier = _getPoolIdentifier(_epoch, _pid);
        bytes32 rewardIdentifier = _getTokenIdentifier(_epoch, _pid, _token);

        Bribe storage bribe = bribesForVePendle[rewardIdentifier];
        bribe._amount += afterFee;
        if(bribe._token == address(0)) {
            bribe._token = _token;
            bribesInPoolForVePendle[poolIdentifier].push(rewardIdentifier);
        }

        emit NewBribeForVePendle(msg.sender, _epoch, _pid, _token, afterFee);
    }

    /* ============ Admin Functions ============ */

    /// @notice this function will create a new pool in the bribeManager and voteManager
    function newPool(address _market, uint256 _chainId) external onlyOwner {
        if (_market == address(0)) revert ZeroAddress();

        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i]._market == _market) {
                revert MarketExists();
            }
        }

        Pool memory pool = Pool(_market, true, _chainId);
        pools.push(pool);

        marketToPid[_market] = pools.length - 1;

        IPendleVoteManager(voteManager).addPool(_market, _chainId);

        emit NewPool(_market, _chainId);
    }

    function removePool(uint256 _pid) external onlyOwner {
        if (_pid >= pools.length) revert InvalidPool();
        pools[_pid]._active = false;
        IPendleVoteManager(voteManager).removePool(_pid);
    }

    function updatePool(uint256 _pid, uint256 _chainId, address _market, bool _active) external onlyOwner {
        if (_pid >= pools.length) revert InvalidPool();
        Pool storage pool = pools[_pid];
        pool._chainId = _chainId;
        pool._market = _market;
        pool._active = _active;
        emit UpdatePool(_pid, _chainId, _market, _active);
    }

    function forceSetMarketPID(address _market, uint256 _newPid) external onlyOwner {
        marketToPid[_market] = _newPid;
        emit MarketPIDForceSet(_market, _newPid);
    }

    function forcePopLastPool() external onlyOwner {
        if (pools.length == 0) revert InvalidPool();
        pools.pop();
    }

    function forcePushEpoch(uint256 _epoch, uint256 _time) external onlyOwner {
        epochStartTime = _time;
        currentEpoch = _epoch;

        emit EpochForcePushed(currentEpoch, _time);
    }

    function setEpochPeriod(uint256 _epochPeriod) external onlyOwner {
        epochPeriod = _epochPeriod;
        emit EpochPeriodSet(_epochPeriod);
    }

    function addAllowedTokens(address _token) external onlyOwner {
        if (allowedToken[_token]) revert InvalidBribeToken();

        allowedTokens.push(_token);

        allowedToken[_token] = true;
        emit AllowedTokenAdded(_token);
    }

    function removeAllowedTokens(address _token) external onlyOwner {
        if (!allowedToken[_token]) revert InvalidBribeToken();
        uint256 allowedTokensLength = allowedTokens.length;
        uint256 i = 0;
        while (allowedTokens[i] != _token) {
            i++;
            if (i >= allowedTokensLength) revert InvalidBribeToken();
        }

        allowedTokens[i] = allowedTokens[allowedTokensLength-1];
        allowedTokens.pop();

        allowedToken[_token] = false;
        emit AllowedTokenRemoved(_token);
    }

    function updateAllowedOperator(address _user, bool _allowed) external onlyOwner {
        allowedOperator[_user] = _allowed;

        emit UpdateOperatorStatus(_user, _allowed);
    }

    function setPendleMarketRegisterHelper(address _pendleMarketRegisterHelper) external onlyOwner {
        if (_pendleMarketRegisterHelper == address(0)) revert ZeroAddress();
        pendleMarketRegisterHelper = _pendleMarketRegisterHelper;

        emit PendleMarketRegisterHelperSet(_pendleMarketRegisterHelper);
    }

    function setDistributor(address payable _distributor) external onlyOwner {
        if (_distributor == address(0)) revert ZeroAddress();
        distributor= _distributor;

        emit DistributorSet(_distributor);
    }

    function setFeeCollector(address payable _collector) external onlyOwner {
        if (_collector == address(0)) revert ZeroAddress();
        feeCollector = _collector;

        emit FeeCollectorSet(_collector);
    }

    function setFeeRatio(uint256 _feeRatio) external onlyOwner {
        require(_feeRatio <= DENOMINATOR, "Fee Ratio cannot be greater than 100%.");
        feeRatio = _feeRatio;

        emit FeeRatioSet(_feeRatio);
    }

    function setDistributorForVePendle(address payable _distributorForVePendle) external onlyOwner {
        if (_distributorForVePendle == address(0)) revert ZeroAddress();
        distributorForVePendle = _distributorForVePendle;

        emit DistributorForVePendleSet(_distributorForVePendle);
    }

    function setPnpBribingRatio(uint256 _pnpBribingRatio) external onlyOwner {
        require(_pnpBribingRatio <= DENOMINATOR, "PNP Bribing Ratio cannot be greater than 100%.");
        pnpBribingRatio = _pnpBribingRatio;

        emit PNPBribingRatioSet(_pnpBribingRatio);
    }

    function manualClaimFees(address _token) external onlyOwner {
        if (feeCollector != address(0)) {
            uint256 unCollectedFeeAmount = unCollectedFee[_token];
            unCollectedFee[_token] = 0;
            if (_token == NATIVE) {
                feeCollector.call{value: unCollectedFeeAmount}("");
            } else {
                IERC20(_token).safeTransfer(feeCollector, unCollectedFeeAmount);
            }
        }
    }

    function reallocateBribe(
        uint256 _epochFrom,
        uint256 _epochTo,
        uint256 _pid,
        address _token,
        uint256 _amount,
        bool forVePendle
    ) external onlyOwner {
        if (_pid >= pools.length || !pools[_pid]._active) revert InvalidPool();
        if (!allowedToken[_token] && _token != NATIVE) revert InvalidBribeToken();

        if (_epochFrom < exactCurrentEpoch() - 1 || _epochTo < exactCurrentEpoch() - 1) revert InvalidEpoch();
        if (_amount == 0) revert ZeroAmount();

        bytes32 rewardIdentifierFrom = _getTokenIdentifier(_epochFrom, _pid, _token);

        Bribe storage bribeFrom = forVePendle
            ? bribesForVePendle[rewardIdentifierFrom]
            : bribes[rewardIdentifierFrom];

        if (bribeFrom._token == address(0)) revert InvalidBribeToken();

        if (bribeFrom._amount < _amount) revert InsufficientAmount();

        bribeFrom._amount -= _amount;

        bytes32 poolIdentifierTo = _getPoolIdentifier(_epochTo, _pid);
        bytes32 rewardIdentifierTo = _getTokenIdentifier(_epochTo, _pid, _token);

        Bribe storage bribeTo = forVePendle
            ? bribesForVePendle[rewardIdentifierTo]
            : bribes[rewardIdentifierTo];
        bribeTo._amount += _amount;
        if (bribeTo._token == address(0)) {
            bribeTo._token = _token;
            if (forVePendle) bribesInPoolForVePendle[poolIdentifierTo].push(rewardIdentifierTo);
            else bribesInPool[poolIdentifierTo].push(rewardIdentifierTo);
        }

        emit BribeReallocated(_pid, _token, _epochFrom, _epochTo, _amount);
    }

	function pause() public onlyOwner {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}
}