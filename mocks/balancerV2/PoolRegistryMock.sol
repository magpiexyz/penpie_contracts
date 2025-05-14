// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";

import "./VaultAuthorizationMock.sol";

abstract contract PoolRegistryMock is ReentrancyGuard, VaultAuthorizationMock {
    mapping(bytes32 => bool) private _isPoolRegistered;
    uint256 private _nextPoolNonce;
    modifier withRegisteredPool(bytes32 poolId) {
        _ensureRegisteredPool(poolId);
        _;
    }
    modifier onlyPool(bytes32 poolId) {
        _ensurePoolIsSender(poolId);
        _;
    }
 
    function _ensureRegisteredPool(bytes32 poolId) internal view {
        _require(_isPoolRegistered[poolId], Errors.INVALID_POOL_ID);
    }

    function _ensurePoolIsSender(bytes32 poolId) private view {
        _ensureRegisteredPool(poolId);
        _require(msg.sender == _getPoolAddress(poolId), Errors.CALLER_NOT_POOL);
    }

    function registerPool(PoolSpecialization specialization)
        external
        override
        nonReentrant
        whenNotPaused
        returns (bytes32)
    {
        bytes32 poolId = _toPoolId(msg.sender, specialization, uint80(_nextPoolNonce));

        _require(!_isPoolRegistered[poolId], Errors.INVALID_POOL_ID); // Should never happen as Pool IDs are unique.
        _isPoolRegistered[poolId] = true;

        _nextPoolNonce += 1;

        emit PoolRegistered(poolId, msg.sender, specialization);
        return poolId;
    }

    function getPool(bytes32 poolId)
        external
        view
        override
        withRegisteredPool(poolId)
        returns (address, PoolSpecialization)
    {
        return (_getPoolAddress(poolId), _getPoolSpecialization(poolId));
    }
    function _toPoolId(
        address pool,
        PoolSpecialization specialization,
        uint80 nonce
    ) internal pure returns (bytes32) {
        bytes32 serialized;

        serialized |= bytes32(uint256(nonce));
        serialized |= bytes32(uint256(specialization)) << (10 * 8);
        serialized |= bytes32(uint256(pool)) << (12 * 8);

        return serialized;
    }

    function _getPoolAddress(bytes32 poolId) internal pure returns (address) {
        return address(uint256(poolId) >> (12 * 8));
    }

    function _getPoolSpecialization(bytes32 poolId) internal pure returns (PoolSpecialization specialization) {
        uint256 value = uint256(poolId >> (10 * 8)) & (2**(2 * 8) - 1);
        _require(value < 3, Errors.INVALID_POOL_ID);
        assembly {
            specialization := value
        }
    }
}
