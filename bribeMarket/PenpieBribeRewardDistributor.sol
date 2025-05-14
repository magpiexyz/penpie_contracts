// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "../libraries/math/Math.sol";
import "../libraries/batchSwapHelper.sol";

/// @title PenpieBribeRewardDistributor
/// @notice Penpie bribe reward distributor is used for distributing rewards from voting.
///         We aggregate all reward tokens for each user who voted on any pools off-chain,
///         so that users can claim their rewards by simply looping through and saving on
///         gas costs.
///         When importing the merkleTree, we will include the previous amount of users
///         and record the claimed amount for each user, ensuring that users always receive
///         the correct amount of rewards.
///
/// @author Magpie Team
contract PenpieBribeRewardDistributor is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct Distribution {
        address token;
        bytes32 merkleRoot;
    }

    struct Reward {
        bytes32 merkleRoot;
        bytes32 proof;
        uint256 updateCount;
    }

    struct Claimable {
        address token;
        uint256 amount;
    }

    struct Claim {
        address token;
        address account;
        uint256 amount;
        bytes32[] merkleProof;
    }

    /* ============ State Variables ============ */

    address constant NATIVE = address(1);
    address public bribeManager;

    mapping(address => Reward) public rewards; // Maps each of the token to its reward metadata
    mapping(address => mapping(address => uint256)) public claimed; // Tracks the amount of claimed reward for the specified token+account
    mapping(address => bool) public allowedOperator;

    /* ============ 1st Upgrade ============ */
    address public odosRouter;

    /* ============ Events ============ */

    event RewardClaimed(
        address indexed token,
        address indexed account,
        uint256 amount,
        uint256 updateCount
    );
    event RewardMetadataUpdated(
        address indexed token,
        bytes32 merkleRoot,
        uint256 indexed updateCount
    );
    event UpdateOperatorStatus(
        address indexed _user, 
        bool _status
    );
    event UpdateBribeManager(
        address _oldManager,
        address _newManager
    );
    event RewardClaimedAsSpecificToken(
        address[] indexed tokens,
        address indexed tokenOut,
        uint256 totalAmountSwappedOut,
        address indexed account
    );
    event UpdatedOdosRouter(
        address indexed updatedOdosRouter
    );
    event NativeRewardsSentBack(
        address indexed user,
        uint256 amount
    );
    event RewardsSentBack(
        address indexed rewardToken,
        address indexed user,
        uint256 amount
    );
     

    /* ============ Errors ============ */

    error OnlyOperator();
    error DistributionNotEnabled();
    error InvalidProof();
    error InsufficientClaimable();
    error TransferFailed();
    error InvalidDistributions();
    error NotValidAccount();

    /* ============ Constructor ============ */
    constructor() {
        _disableInitializers();
    }

    function __PenpieBribeRewardDistributor_init(
        address _bribeManager
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        bribeManager = _bribeManager;
        allowedOperator[owner()] = true;
    }

    /* ============ Modifiers ============ */

    modifier onlyOperator() {
        if (!allowedOperator[msg.sender]) revert OnlyOperator();
        _;
    }

    /* ============ External Getters ============ */

    /* ============ External Functions ============ */

    receive() external payable { }

    function getClaimable(Claim[] calldata _claims) external view returns(Claimable[] memory) {
        Claimable[] memory claimables = new Claimable[](_claims.length);

        for (uint256 i; i < _claims.length; ++i) {
            claimables[i] = Claimable(
                _claims[i].token,
                _claimable(
                    _claims[i].token,
                    _claims[i].account,
                    _claims[i].amount,
                    _claims[i].merkleProof
                )
            );
        }

        return claimables;
    }

    function claim(Claim[] calldata _claims) external nonReentrant whenNotPaused {
        for (uint256 i; i < _claims.length; ++i) {
            _claim(
                _claims[i].token,
                _claims[i].account,
                _claims[i].amount,
                _claims[i].merkleProof
            );
        }
    }

    /**
        @notice Claim a reward
        @param  _transactionData  transaction data excluding WETH.
        @param  _claims   reward _claims data.
     */
    function claimAsSpecificToken(bytes[] calldata _transactionData, Claim[] calldata _claims, address _tokenForSwapOut) external nonReentrant whenNotPaused onlyOperator {
        address[] memory tokensForSwap = new address[](_claims.length);
        uint256[] memory tokenAmountsForSwap = new uint256[](_claims.length);
        uint256 tokenForSwapAndAmountIndex = 0;
    
        for (uint256 i; i < _claims.length; ++i) {
            if(_claims[i].account != msg.sender) revert NotValidAccount();

            uint256 claimable = _claimable(
                    _claims[i].token,
                    _claims[i].account,
                    _claims[i].amount,
                    _claims[i].merkleProof
            );

            if(claimable == 0) revert InsufficientClaimable();

            claimed[_claims[i].token][_claims[i].account] += claimable;
            if(_claims[i].token == NATIVE)
            {
                (bool sent, ) = payable(_claims[i].account).call{ value: claimable }("");
                if (!sent) revert TransferFailed();
                emit NativeRewardsSentBack(_claims[i].account, claimable);
            }
            else if(_claims[i].token == _tokenForSwapOut)
            {
                IERC20(_claims[i].token).safeTransfer(_claims[i].account, claimable);
                emit RewardsSentBack(_claims[i].token, _claims[i].account, claimable);
            } 
            else 
            {
                tokensForSwap[tokenForSwapAndAmountIndex] = _claims[i].token;
                tokenAmountsForSwap[tokenForSwapAndAmountIndex] = claimable;
                tokenForSwapAndAmountIndex++;
            }
        }

        if(tokenForSwapAndAmountIndex > 0)
        {
            uint256 totalSwappedAmount = _batchSwap(_transactionData, tokensForSwap, tokenAmountsForSwap, _tokenForSwapOut, msg.sender, tokenForSwapAndAmountIndex);
            emit RewardClaimedAsSpecificToken(tokensForSwap, _tokenForSwapOut, totalSwappedAmount, msg.sender);
        }
    }

    /* ============ Internal Functions ============ */

    /**
        @notice Claim a reward
        @param  _token             address    Token address
        @param  _account           address    Eligible user account
        @param  _amount            uint256    Reward amount
        @param  _merkleProof       bytes32[]  Merkle proof
     */
    function _claimable(
        address _token,
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) private view returns(uint256 claimable) {
        Reward memory reward = rewards[_token];

        if (reward.merkleRoot == 0) revert DistributionNotEnabled();

        // Verify the merkle proof
        if (
            !MerkleProof.verify(
                _merkleProof,
                reward.merkleRoot,
                keccak256(abi.encodePacked(_account, _amount))
            )
        ) revert InvalidProof();

        // Verify the claimable amount
        if (claimed[_token][_account] >= _amount) {
            claimable = 0;
        } else {
            // Calculate the claimable amount based off the total of reward (used in the merkle tree)
            // since the beginning for the user, minus the total claimed so far
            claimable = _amount - claimed[_token][_account];
        }
    }

    /**
        @notice Claim a reward
        @param  _token             address    Token address
        @param  _account           address    Eligible user account
        @param  _amount            uint256    Reward amount
        @param  _merkleProof       bytes32[]  Merkle proof
     */
    function _claim(
        address _token,
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) private {
        Reward memory reward = rewards[_token];

        if (reward.merkleRoot == 0) revert DistributionNotEnabled();

        // Verify the merkle proof
        if (
            !MerkleProof.verify(
                _merkleProof,
                reward.merkleRoot,
                keccak256(abi.encodePacked(_account, _amount))
            )
        ) revert InvalidProof();

        // Verify the claimable amount
        if (claimed[_token][_account] >= _amount)
            revert InsufficientClaimable();

        // Calculate the claimable amount based off the total of reward (used in the merkle tree)
        // since the beginning for the user, minus the total claimed so far
        uint256 claimable = _amount - claimed[_token][_account];
        // Update the claimed amount to the current total
        claimed[_token][_account] = _amount;

        // Check whether the reward is in the form of native tokens or ERC20
        // by checking if the token address is set to NATIVE
        if (_token != NATIVE) {
            IERC20(_token).safeTransfer(_account, claimable);
        } else {
            (bool sent, ) = payable(_account).call{ value: claimable }("");
            if (!sent) revert TransferFailed();
        }

        emit RewardClaimed(_token, _account, claimable, reward.updateCount);
    }

    function _batchSwap(
        bytes[] calldata _transactionData,
        address[] memory _tokensForSwap, 
        uint256[] memory _tokenAmountsForSwap,
        address _tokenForSwapOut,
        address _reciever,
        uint256 totalTokenForSwapLength
    ) internal returns (uint256) { 
        address[] memory tokensForSwap = new address[](totalTokenForSwapLength);
        uint256[] memory tokenAmountsForSwap = new uint256[](totalTokenForSwapLength);

        for(uint256 i; i < totalTokenForSwapLength; ++i) {
            tokensForSwap[i] = _tokensForSwap[i];
            tokenAmountsForSwap[i] = _tokenAmountsForSwap[i];
        }

        uint256 totalSwappedAmount =  batchSwapHelper.batchSwap(_transactionData, tokensForSwap, tokenAmountsForSwap, _tokenForSwapOut, _reciever, odosRouter);
        return totalSwappedAmount;
    }

    /* ============ Admin Functions ============ */

    function updateDistribution(
        Distribution[] calldata _distributions
    ) external onlyOperator {
        if (_distributions.length == 0) revert InvalidDistributions();

        for (uint256 i; i < _distributions.length; ++i) {
            // Update the metadata and also increment the update counter
            Distribution calldata distribution = _distributions[i];
            Reward storage reward = rewards[distribution.token];
            reward.merkleRoot = distribution.merkleRoot;
            ++reward.updateCount;

            emit RewardMetadataUpdated(
                distribution.token,
                distribution.merkleRoot,
                reward.updateCount
            );
        }
    }

    function emergencyWithdraw(address _token, address _receiver) external onlyOwner {
        if (_token == NATIVE) {
            address payable recipient = payable(_receiver);
            recipient.call{value: address(this).balance}("");
        } else {
            IERC20(_token).safeTransfer(
                _receiver,
                IERC20(_token).balanceOf(address(this))
            );
        }
    }

    function setBribeManager(address _manager) external onlyOwner {
        address oldManager = bribeManager;
        bribeManager = _manager;
        emit UpdateBribeManager(oldManager, _manager);
    }

    function setOdosRouter(address _odosRouter) external onlyOwner {
        odosRouter = _odosRouter;
        emit UpdatedOdosRouter(_odosRouter);
    }

    function updateAllowedOperator(address _user, bool _allowed) external onlyOwner {
        allowedOperator[_user] = _allowed;

        emit UpdateOperatorStatus(_user, _allowed);
    }

	function pause() public onlyOperator {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}
}