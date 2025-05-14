// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

import "./BalanceAllocationMock.sol";
import "../PoolRegistryMock.sol";

abstract contract MinimalSwapInfoPoolsBalanceMock is PoolRegistryMock {
    using BalanceAllocationMock for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 => mapping(IERC20 => bytes32)) internal _minimalSwapInfoPoolsBalances;
    mapping(bytes32 => EnumerableSet.AddressSet) internal _minimalSwapInfoPoolsTokens;

    function _registerMinimalSwapInfoPoolTokens(bytes32 poolId, IERC20[] memory tokens) internal {
        EnumerableSet.AddressSet storage poolTokens = _minimalSwapInfoPoolsTokens[poolId];

        for (uint256 i = 0; i < tokens.length; ++i) {
            bool added = poolTokens.add(address(tokens[i]));
            _require(added, Errors.TOKEN_ALREADY_REGISTERED);
        }
    }

    function _deregisterMinimalSwapInfoPoolTokens(bytes32 poolId, IERC20[] memory tokens) internal {
        EnumerableSet.AddressSet storage poolTokens = _minimalSwapInfoPoolsTokens[poolId];

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            _require(_minimalSwapInfoPoolsBalances[poolId][token].isZero(), Errors.NONZERO_TOKEN_BALANCE);

            delete _minimalSwapInfoPoolsBalances[poolId][token];

            bool removed = poolTokens.remove(address(token));
            _require(removed, Errors.TOKEN_NOT_REGISTERED);
        }
    }

    function _setMinimalSwapInfoPoolBalances(
        bytes32 poolId,
        IERC20[] memory tokens,
        bytes32[] memory balances
    ) internal {
        for (uint256 i = 0; i < tokens.length; ++i) {
            _minimalSwapInfoPoolsBalances[poolId][tokens[i]] = balances[i];
        }
    }

    function _minimalSwapInfoPoolCashToManaged(
        bytes32 poolId,
        IERC20 token,
        uint256 amount
    ) internal {
        _updateMinimalSwapInfoPoolBalance(poolId, token, BalanceAllocationMock.cashToManaged, amount);
    }

    function _minimalSwapInfoPoolManagedToCash(
        bytes32 poolId,
        IERC20 token,
        uint256 amount
    ) internal {
        _updateMinimalSwapInfoPoolBalance(poolId, token, BalanceAllocationMock.managedToCash, amount);
    }

    function _setMinimalSwapInfoPoolManagedBalance(
        bytes32 poolId,
        IERC20 token,
        uint256 amount
    ) internal returns (int256) {
        return _updateMinimalSwapInfoPoolBalance(poolId, token, BalanceAllocationMock.setManaged, amount);
    }

    function _updateMinimalSwapInfoPoolBalance(
        bytes32 poolId,
        IERC20 token,
        function(bytes32, uint256) returns (bytes32) mutation,
        uint256 amount
    ) internal returns (int256) {
        bytes32 currentBalance = _getMinimalSwapInfoPoolBalance(poolId, token);

        bytes32 newBalance = mutation(currentBalance, amount);
        _minimalSwapInfoPoolsBalances[poolId][token] = newBalance;

        return newBalance.managedDelta(currentBalance);
    }

    function _getMinimalSwapInfoPoolTokens(bytes32 poolId)
        internal
        view
        returns (IERC20[] memory tokens, bytes32[] memory balances)
    {
        EnumerableSet.AddressSet storage poolTokens = _minimalSwapInfoPoolsTokens[poolId];
        tokens = new IERC20[](poolTokens.length());
        balances = new bytes32[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = IERC20(poolTokens.unchecked_at(i));
            tokens[i] = token;
            balances[i] = _minimalSwapInfoPoolsBalances[poolId][token];
        }
    }

    function _getMinimalSwapInfoPoolBalance(bytes32 poolId, IERC20 token) internal view returns (bytes32) {
        bytes32 balance = _minimalSwapInfoPoolsBalances[poolId][token];
        bool tokenRegistered = balance.isNotZero() || _minimalSwapInfoPoolsTokens[poolId].contains(address(token));

        if (!tokenRegistered) {
            _ensureRegisteredPool(poolId);
            _revert(Errors.TOKEN_NOT_REGISTERED);
        }

        return balance;
    }

    function _isMinimalSwapInfoPoolTokenRegistered(bytes32 poolId, IERC20 token) internal view returns (bool) {
        EnumerableSet.AddressSet storage poolTokens = _minimalSwapInfoPoolsTokens[poolId];
        return poolTokens.contains(address(token));
    }
}
