// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IMasterPenpie.sol";
import "../interfaces/IBaseRewardPool.sol";

/// @notice MasterChef refers to contracts like MasterMagpie, MasterPenpie, MasterRadpie....
/// @notice Here currently staking tokens from different masterChefs (masterMagpie, masterPenpie, masterRadpie)
/// are used to differentiate between pools; for masterMagpie, the staking token is the receipt token;
/// for masterPenpie the staking token is the Pendle Market; for masterRadpie it is the asset token i.e. the deposit token
/// If trying to extend this contract to other protocols, keep in mind that the staking token should not be same as any
/// of the other protocol's staking tokens or it will cause problems.

contract ARBRewarder is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct PoolInfo {
        uint256 ARBPerSec;
        uint256 lastRewardTimestamp;
        address masterChef;
        bool isActive;
        uint256 endTimestamp;
    }

    /* ============ State Variables ============ */

    IERC20 public ARB;

    // Info of each pool by tokenToPoolInfo[stakingToken]
    mapping(address => PoolInfo) public tokenToPoolInfo;

    address[] public registeredPools;

    /* ============ Events ============ */

    event UpdateEmissionRate(address indexed _user, uint256 _oldARBPerSec, uint256 _newARBPerSec);
    event ARBSet(address _ARB);
    event ARBRewadsSent(
        address _stakingToken, address _rewarder, uint256 _totalARBSent, uint256 lastRewardTimestamp, uint256 ARBPerSec
    );
    event registeredPool(address _stakingToken, uint256 _arbPersec, address _masterChef);
    event SetPool(address _stakingToken, address _masterChef, bool _isActive, uint256 _endTimestamp);

    /* ============ Errors ============ */

    error ARBSetAlready();
    error MustBeContract();
    error onlymasterChef();
    error PoolAlreadyAdded();
    error LengthMismatch();
    error ZeroAddress();
    error InvalidEndtime();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __ARBRewarder_init(address _ARB) public initializer {
        __Ownable_init();
        __Pausable_init();
        ARB = IERC20(_ARB);
    }

    /* ============ Modifiers ============ */

    modifier _onlyMasterChef(address _stakingToken) {
        address masterChef = tokenToPoolInfo[_stakingToken].masterChef;
        if (masterChef != msg.sender) {
            revert onlymasterChef();
        }
        _;
    }

    /* ============ External Getters ============ */

    function poolLength() external view returns (uint256) {
        return registeredPools.length;
    }

    /* ============ External Functions ============ */

    function massUpdatePools() public whenNotPaused {
        for (uint256 pid = 0; pid < registeredPools.length; ++pid) {
            address stakingToken = registeredPools[pid];
            PoolInfo memory pool = tokenToPoolInfo[stakingToken];
            if (!pool.isActive || pool.ARBPerSec == 0 || block.timestamp == pool.lastRewardTimestamp) {
                continue;
            }
            address rewarder = IMasterPenpie(pool.masterChef).getRewarder(stakingToken);
            _calculateAndSendARB(stakingToken, rewarder);
        }
    }

    function harvestARB(address stakingToken, address rewarder) external _onlyMasterChef(stakingToken) whenNotPaused {
        _calculateAndSendARB(stakingToken, rewarder);
    }

    /* ============ Internal Functions ============ */

    function _calculateAndSendARB(address _stakingToken, address _rewarder) internal {
        if (_rewarder == address(0)) {
            return;
        }
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        if (!pool.isActive || pool.ARBPerSec == 0 || block.timestamp == pool.lastRewardTimestamp) {
            return;
        }

        uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
        if (block.timestamp >= pool.endTimestamp) {
            pool.isActive = false;
            multiplier = pool.endTimestamp - pool.lastRewardTimestamp;
        }
        uint256 rewardAmount = (multiplier * pool.ARBPerSec);
        rewardAmount = Math.min(rewardAmount, ARB.balanceOf(address(this)));
        pool.lastRewardTimestamp = block.timestamp;

        ARB.approve(_rewarder, rewardAmount);
        IBaseRewardPool(_rewarder).queueNewRewards(rewardAmount, address(ARB));
        emit ARBRewadsSent(_stakingToken, _rewarder, rewardAmount, pool.lastRewardTimestamp, pool.ARBPerSec);

    }

    function _addPool(address _stakingToken, uint256 _arbPerSec, address _masterChef, uint256 _endTimestamp) internal {
        if (_masterChef == address(0)) {
            revert ZeroAddress();
        }
        if(tokenToPoolInfo[_stakingToken].masterChef != address(0)) {
            revert PoolAlreadyAdded();
        }

        tokenToPoolInfo[_stakingToken] = PoolInfo({
            ARBPerSec: _arbPerSec,
            lastRewardTimestamp: block.timestamp,
            masterChef: _masterChef,
            isActive: true,
            endTimestamp: _endTimestamp
        });

        registeredPools.push(_stakingToken);
        emit registeredPool(_stakingToken, _arbPerSec, _masterChef);
    }

    /* ============ Admin Functions ============ */

    function setARB(address _ARB) external onlyOwner {
        if (address(ARB) != address(0)) revert ARBSetAlready();
        if (!Address.isContract(_ARB)) revert MustBeContract();

        ARB = IERC20(_ARB);
        emit ARBSet(_ARB);
    }

    /**
     * @dev pause pool, restricting certain operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, enabling certain operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Update the emission rate of ARB
    /// @param _ARBPerSec new emission per second
    function updateEmissionRateFor(address stakingToken, uint256 _ARBPerSec) public onlyOwner {
        PoolInfo storage pool = tokenToPoolInfo[stakingToken];
        address rewarder = IMasterPenpie(pool.masterChef).getRewarder(stakingToken);
        _calculateAndSendARB(stakingToken, rewarder);

        uint256 oldEmissionRate = tokenToPoolInfo[stakingToken].ARBPerSec;
        pool.ARBPerSec = _ARBPerSec;

        emit UpdateEmissionRate(stakingToken, oldEmissionRate, _ARBPerSec);
    }
    /// @param _stakingToken is the array of the staking tokens of the pools to be registered,
    /// for masterMagpie, is is the receipt token; for masterPenpie, it is the Pendle Market;
    /// for masterRadpie, it is the asset token i.e. the deposit token
    ///@param _arbPerSec it is the arbPer second array to be emitted for the pools respectively
    ///@param _masterChefs it is the array of the masterChefs of the pools with the staking tokens in _stakingToken array

    function addPools(
        address[] calldata _stakingToken,
        uint256[] calldata _arbPerSec,
        address[] calldata _masterChefs,
        uint256[] calldata _endTimestamps
    ) external onlyOwner {
        if (
            _stakingToken.length != _arbPerSec.length || _stakingToken.length != _masterChefs.length
                || _stakingToken.length != _endTimestamps.length
        ) {
            revert LengthMismatch();
        }
        for (uint256 index = 0; index < _stakingToken.length; index++) {
            _addPool(_stakingToken[index], _arbPerSec[index], _masterChefs[index], _endTimestamps[index]);
        }
    }

    function setPool(address _stakingToken, address _masterChef, bool _isActive, uint256 _endTimestamp)
        external
        onlyOwner
    {
        if (_masterChef == address(0)) {
            revert ZeroAddress();
        }
        if (_endTimestamp < block.timestamp) {
            revert InvalidEndtime();
        }

        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];

        if (pool.isActive && (!_isActive || (pool.masterChef != _masterChef))) {
            // if setting an active pool to inactive or updating the masterchef, queue the pending arb rewards to rewarder
            address rewarder = IMasterPenpie(pool.masterChef).getRewarder(_stakingToken);
            _calculateAndSendARB(_stakingToken, rewarder);
        }
        if (!pool.isActive && _isActive) {
            // if setting an inactive pool as active, just set the current timestamp as lastRewardTimestamp
            pool.lastRewardTimestamp = block.timestamp;
        }
        pool.masterChef = _masterChef;
        pool.isActive = _isActive;
        pool.endTimestamp = _endTimestamp;

        emit SetPool(_stakingToken, _masterChef, _isActive, _endTimestamp);
    }
}
