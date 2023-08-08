// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./libraries/BoringOwnableUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "../../libraries/TokenHelper.sol";
import "../../libraries/Errors.sol";
import "../../interfaces/pendle/IPFeeDistributorV2.sol";

contract PendleFeeDistributorV2Mock is
    Ownable,
    IPFeeDistributorV2,
    TokenHelper
{
    bytes32 public merkleRoot;

    struct ProtocolData {
        mapping(address => uint256) claimable;
        uint256 totalAccrued;
    }

    mapping(address => uint256) public claimed;

    mapping(address => ProtocolData) internal protocol;

    constructor() {}

    receive() external payable {}

    function claimRetail(
        address receiver,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountOut) {
        address user = msg.sender;
        if (!_verifyMerkleData(user, totalAccrued, proof)) revert Errors.InvalidMerkleProof();

        amountOut = totalAccrued - claimed[user];
        claimed[user] = totalAccrued;

        // assert(claimed[user] <= totalAccrued); // important invariant, obviously true

        // transfer ETH last
        _transferOut(NATIVE, receiver, amountOut);
        emit Claimed(user, amountOut);
    }

    function claimProtocol(address receiver, address[] calldata pools)
        external
        returns (uint256 totalAmountOut, uint256[] memory amountsOut)
    {
        unchecked {
            address user = msg.sender;

            uint256 nPools = pools.length;
            amountsOut = new uint256[](nPools);

            for (uint256 i = 0; i < nPools; i++) {
                amountsOut[i] = protocol[user].claimable[pools[i]];
                if (amountsOut[i] == 0) continue;

                amountsOut[i]--;
                totalAmountOut += amountsOut[i];

                protocol[user].claimable[pools[i]] = 1;
            }

            claimed[user] += totalAmountOut;
            assert(claimed[user] <= protocol[user].totalAccrued); // important invariant, must always hold regardless of claimable mapping

            // transfer ETH last
            _transferOut(NATIVE, receiver, totalAmountOut);
            emit Claimed(user, totalAmountOut);
        }
    }

    function getProtocolClaimables(address user, address[] calldata pools)
        external
        view
        returns (uint256[] memory claimables)
    {
        unchecked {
            uint256 nPools = pools.length;
            claimables = new uint256[](nPools);

            for (uint256 i = 0; i < nPools; i++) {
                claimables[i] = protocol[user].claimable[pools[i]];
                if (claimables[i] == 0) continue;

                claimables[i]--;
            }
        }
    }

    function getProtocolTotalAccrued(address user) external view returns (uint256) {
        return protocol[user].totalAccrued;
    }

    function _verifyMerkleData(
        address user,
        uint256 amount,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user, amount));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    // ----------------- owner logic -----------------
    function setMerkleRootAndFund(bytes32 newMerkleRoot, uint256 amountToFund)
        external
        payable
        onlyOwner
    {
        _transferIn(NATIVE, msg.sender, amountToFund);
        merkleRoot = newMerkleRoot;
        emit SetMerkleRootAndFund(newMerkleRoot, amountToFund);
    }

    /// @dev no onlyOwner, only calls an onlyOwner function
    function updateProtocolClaimables(UpdateProtocolStruct[] calldata arr) external {
        unchecked {
            for (uint256 i = 0; i < arr.length; i++) {
                // updateProtocolClaimable(arr[i]);
            }
        }
    }

    function updateProtocolClaimable(address user, uint256[] calldata topUps, address[] calldata pools) public onlyOwner {
        uint256 nPools = pools.length;
        uint256 sumTopUps;

        for (uint256 i = 0; i < nPools; i++) {
            protocol[user].claimable[pools[i]] += topUps[i];
            sumTopUps += topUps[i];
        }

        uint256 newTotalAccrued = protocol[user].totalAccrued + sumTopUps;

        protocol[user].totalAccrued = newTotalAccrued;
        emit UpdateProtocolClaimable(user, sumTopUps);
    }

    // ----------------- upgrade-related -----------------

    function _authorizeUpgrade(address) internal onlyOwner {}
}