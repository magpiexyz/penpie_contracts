// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { PendleStakingBaseUpg } from "./PendleStakingBaseUpg.sol";
import { IPMerkleDistributor } from "../interfaces/pendle/IPMerkleDistributor.sol";
import "../interfaces/IBaseRewardPool.sol";

/// @title PendleStakingSideChain
/// @notice PendleStaking Side only get vePendle posistion broadcast from main chain to get boosting yield effect
///         
/// @author Magpie Team

contract PendleStakingSideChain is PendleStakingBaseUpg {
    using SafeERC20 for IERC20;

    /* ===== 1st upgrade ===== */
    address public ARB;
    Fees[] public ARBFeeInfos;

    constructor() {_disableInitializers();}

    /* ============ Events ============ */
    event AddARBFee(address _to, uint256 _value, bool _isAddress);
    event ARBFeeUpdated(uint256 _index, address _to, uint256 _value, bool _isAddress, bool _isActive);
    event ARBAddressUpdated(address _oldARBAddress, address _ARBAddress);
    event FeePaidTo(address _to, address _token, uint256 value, bool _isAddress);

    /* ============ Errors ============ */
    error NotSupported();
    error NotEnoughClaim();

    function __PendleStakingSideChain_init(
        address _pendle,
        address _WETH,
        address _vePendle,
        address _distributorETH,
        address _pendleRouter,
        address _masterPenpie
    ) public initializer {
        __PendleStakingBaseUpg_init(
            _pendle,
            _WETH,
            _vePendle,
            _distributorETH,
            _pendleRouter,
            _masterPenpie
        );
    }

     /* ============ VePendle Related Functions ============ */

    /// @notice convert PENDLE to mPendle
    /// @param _amount the number of Pendle to convert
    /// @dev the Pendle must already be in the contract
    function convertPendle(
        uint256 _amount,
        uint256[] calldata chainId
    ) public payable override whenNotPaused returns (uint256) {
       revert NotSupported();
    }

    function vote(address[] calldata _pools, uint64[] calldata _weights) external override {
        revert NotSupported();
    }

    /* ================= ARB incentives claim and Queueing ========== */
    function claimAndQueueARB(
        address[] calldata markets,
        uint256[] calldata marketRewardAmount,
        address pendleMerkleDistributor
    ) external onlyOwner {

        uint256 length = markets.length;
        require(length == marketRewardAmount.length && ARBFeeInfos.length !=0 && length != 0, "Invalid ARB Distribution");

        uint256 amountOut = IPMerkleDistributor(pendleMerkleDistributor).claimVerified(address(this));
        uint256 totalRewardAmount = 0;

        for (uint256 index = 0; index < length; index++)
            totalRewardAmount += marketRewardAmount[index];
        
        if (totalRewardAmount > amountOut) revert NotEnoughClaim();
        uint256 totalFeeValue = 0;

        for(uint256 index = 0; index < ARBFeeInfos.length; index++){
            Fees memory feeInfo = ARBFeeInfos[index];
            if(!feeInfo.isActive) continue;

            totalFeeValue += feeInfo.value;
            if(totalFeeValue > DENOMINATOR) revert InvalidFee();
            _sendARBFee(amountOut, feeInfo.to, feeInfo.value, feeInfo.isAddress);
        }
        uint256 remainingAmountValue = DENOMINATOR - totalFeeValue;
        for (uint256 index = 0; index < length; index++) {

            // reduce fee total value from each reward amount to compensate for fee & revenue share sent
            uint256 rewardAfterFee = (remainingAmountValue * marketRewardAmount[index]) / DENOMINATOR; 
            address rewarder = pools[markets[index]].rewarder;
            IERC20(ARB).safeApprove(rewarder, rewardAfterFee);
            IBaseRewardPool(rewarder).queueNewRewards(rewardAfterFee, ARB);
            emit RewardPaidTo(markets[index], rewarder, ARB, rewardAfterFee);
        }
    }

    function setARB(address _ARB) external onlyOwner {
        address oldAddress = ARB;
        ARB = _ARB;
        emit ARBAddressUpdated(oldAddress, ARB);
    }

    function addARBFees(
        address[] calldata _to, 
        uint256[] calldata _value, 
        bool[] calldata _isAddress
    ) external onlyOwner {

        if(_to.length != _value.length || _to.length != _isAddress.length) revert LengthMismatch();

        for (uint256 index = 0; index < _to.length; index++) {
            require(_to[index] != address(0) && _value[index] <= DENOMINATOR, "Invalid fee parameters");
            ARBFeeInfos.push(
                Fees({
                    value: _value[index],
                    to: _to[index],
                    isMPENDLE: false,
                    isAddress: _isAddress[index],
                    isActive: true
                })
            );
            emit AddARBFee(_to[index], _value[index], _isAddress[index]);
        }
    }

    function setARBFees(uint256 index, address _to, uint256 _value, bool _isAddress, bool _isActive) external onlyOwner {
        require(
            index >=0 && index< ARBFeeInfos.length && _to != address(0) && _value <= DENOMINATOR,
            "Invalid fee parameters"
        );
        ARBFeeInfos[index].to = _to;
        ARBFeeInfos[index].value = _value;
        ARBFeeInfos[index].isAddress = _isAddress;
        ARBFeeInfos[index].isActive = _isActive;

        emit ARBFeeUpdated(index, _to, _value, _isAddress, _isActive);
    }

    /* ================== Internal Functions ================= */

    function _sendARBFee(uint256 amount, address to, uint256 feeValue, bool isAddress) internal {
        uint256 fee = (feeValue * amount) / DENOMINATOR;
        if(isAddress){
            IERC20(ARB).safeTransfer(to, fee);
        }
        else{
            IERC20(ARB).safeApprove(to, fee);
            IBaseRewardPool(to).queueNewRewards(fee, ARB);
        }
        emit FeePaidTo(to, ARB, fee, isAddress);
    }
}
