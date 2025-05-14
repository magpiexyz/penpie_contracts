// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/InputHelpers.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";

import "./UserBalanceMock.sol";
import "./balances/BalanceAllocationMock.sol";
import "./balances/GeneralPoolsBalanceMock.sol";
import "./balances/MinimalSwapInfoPoolsBalanceMock.sol";
import "./balances/TwoTokenPoolsBalanceMock.sol";

abstract contract AssetManagersMock is
    ReentrancyGuard,
    GeneralPoolsBalanceMock,
    MinimalSwapInfoPoolsBalanceMock,
    TwoTokenPoolsBalanceMock
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    mapping(bytes32 => mapping(IERC20 => address)) internal _poolAssetManagers;

    function managePoolBalance(PoolBalanceOp[] memory ops) external override nonReentrant whenNotPaused {
        PoolBalanceOp memory op;

        for (uint256 i = 0; i < ops.length; ++i) {
            op = ops[i];

            bytes32 poolId = op.poolId;
            _ensureRegisteredPool(poolId);

            IERC20 token = op.token;
            _require(_isTokenRegistered(poolId, token), Errors.TOKEN_NOT_REGISTERED);
            _require(_poolAssetManagers[poolId][token] == msg.sender, Errors.SENDER_NOT_ASSET_MANAGER);

            PoolBalanceOpKind kind = op.kind;
            uint256 amount = op.amount;
            (int256 cashDelta, int256 managedDelta) = _performPoolManagementOperation(kind, poolId, token, amount);

            emit PoolBalanceManaged(poolId, msg.sender, token, cashDelta, managedDelta);
        }
    }
    function _performPoolManagementOperation(
        PoolBalanceOpKind kind,
        bytes32 poolId,
        IERC20 token,
        uint256 amount
    ) private returns (int256, int256) {
        PoolSpecialization specialization = _getPoolSpecialization(poolId);

        if (kind == PoolBalanceOpKind.WITHDRAW) {
            return _withdrawPoolBalance(poolId, specialization, token, amount);
        } else if (kind == PoolBalanceOpKind.DEPOSIT) {
            return _depositPoolBalance(poolId, specialization, token, amount);
        } else {
            // PoolBalanceOpKind.UPDATE
            return _updateManagedBalance(poolId, specialization, token, amount);
        }
    }
    function _withdrawPoolBalance(
        bytes32 poolId,
        PoolSpecialization specialization,
        IERC20 token,
        uint256 amount
    ) private returns (int256 cashDelta, int256 managedDelta) {
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            _twoTokenPoolCashToManaged(poolId, token, amount);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _minimalSwapInfoPoolCashToManaged(poolId, token, amount);
        } else {
            // PoolSpecialization.GENERAL
            _generalPoolCashToManaged(poolId, token, amount);
        }

        if (amount > 0) {
            token.safeTransfer(msg.sender, amount);
        }
        cashDelta = int256(-amount);
        managedDelta = int256(amount);
    }
    function _depositPoolBalance(
        bytes32 poolId,
        PoolSpecialization specialization,
        IERC20 token,
        uint256 amount
    ) private returns (int256 cashDelta, int256 managedDelta) {
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            _twoTokenPoolManagedToCash(poolId, token, amount);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _minimalSwapInfoPoolManagedToCash(poolId, token, amount);
        } else {
            _generalPoolManagedToCash(poolId, token, amount);
        }

        if (amount > 0) {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }
        cashDelta = int256(amount);
        managedDelta = int256(-amount);
    }
    function _updateManagedBalance(
        bytes32 poolId,
        PoolSpecialization specialization,
        IERC20 token,
        uint256 amount
    ) private returns (int256 cashDelta, int256 managedDelta) {
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            managedDelta = _setTwoTokenPoolManagedBalance(poolId, token, amount);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            managedDelta = _setMinimalSwapInfoPoolManagedBalance(poolId, token, amount);
        } else {
            // PoolSpecialization.GENERAL
            managedDelta = _setGeneralPoolManagedBalance(poolId, token, amount);
        }

        cashDelta = 0;
    }
    function _isTokenRegistered(bytes32 poolId, IERC20 token) private view returns (bool) {
        PoolSpecialization specialization = _getPoolSpecialization(poolId);
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            return _isTwoTokenPoolTokenRegistered(poolId, token);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            return _isMinimalSwapInfoPoolTokenRegistered(poolId, token);
        } else {
            // PoolSpecialization.GENERAL
            return _isGeneralPoolTokenRegistered(poolId, token);
        }
    }
}
