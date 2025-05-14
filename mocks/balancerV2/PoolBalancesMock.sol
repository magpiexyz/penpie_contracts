// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IBasePool.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/InputHelpers.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";

import "./FeesMock.sol";
import "./PoolTokensMock.sol";
import "./UserBalanceMock.sol";

abstract contract PoolBalancesMock is FeesMock, ReentrancyGuard, PoolTokensMock, UserBalanceMock {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using BalanceAllocationMock for bytes32;
    using BalanceAllocationMock for bytes32[];

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable override whenNotPaused {
        _joinOrExit(PoolBalanceChangeKind.JOIN, poolId, sender, payable(recipient), _toPoolBalanceChange(request));
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external override {
        _joinOrExit(PoolBalanceChangeKind.EXIT, poolId, sender, recipient, _toPoolBalanceChange(request));
    }

    struct PoolBalanceChange {
        IAsset[] assets;
        uint256[] limits;
        bytes userData;
        bool useInternalBalance;
    }
    function _toPoolBalanceChange(JoinPoolRequest memory request)
        private
        pure
        returns (PoolBalanceChange memory change)
    {
        assembly {
            change := request
        }
    }
    function _toPoolBalanceChange(ExitPoolRequest memory request)
        private
        pure
        returns (PoolBalanceChange memory change)
    {
        assembly {
            change := request
        }
    }

    function _joinOrExit(
        PoolBalanceChangeKind kind,
        bytes32 poolId,
        address sender,
        address payable recipient,
        PoolBalanceChange memory change
    ) private nonReentrant withRegisteredPool(poolId) authenticateFor(sender) {

        InputHelpers.ensureInputLengthMatch(change.assets.length, change.limits.length);

        IERC20[] memory tokens = _translateToIERC20(change.assets);
        bytes32[] memory balances = _validateTokensAndGetBalances(poolId, tokens);
        (
            bytes32[] memory finalBalances,
            uint256[] memory amountsInOrOut,
            uint256[] memory paidProtocolSwapFeeAmounts
        ) = _callPoolBalanceChange(kind, poolId, sender, recipient, change, balances);

        PoolSpecialization specialization = _getPoolSpecialization(poolId);
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            _setTwoTokenPoolCashBalances(poolId, tokens[0], finalBalances[0], tokens[1], finalBalances[1]);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _setMinimalSwapInfoPoolBalances(poolId, tokens, finalBalances);
        } else {
            _setGeneralPoolBalances(poolId, finalBalances);
        }

        bool positive = kind == PoolBalanceChangeKind.JOIN;
        emit PoolBalanceChanged(
            poolId,
            sender,
            tokens,
            _unsafeCastToInt256(amountsInOrOut, positive),
            paidProtocolSwapFeeAmounts
        );
    }

    function _callPoolBalanceChange(
        PoolBalanceChangeKind kind,
        bytes32 poolId,
        address sender,
        address payable recipient,
        PoolBalanceChange memory change,
        bytes32[] memory balances
    )
        private
        returns (
            bytes32[] memory finalBalances,
            uint256[] memory amountsInOrOut,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        (uint256[] memory totalBalances, uint256 lastChangeBlock) = balances.totalsAndLastChangeBlock();

        IBasePool pool = IBasePool(_getPoolAddress(poolId));
        (amountsInOrOut, dueProtocolFeeAmounts) = kind == PoolBalanceChangeKind.JOIN
            ? pool.onJoinPool(
                poolId,
                sender,
                recipient,
                totalBalances,
                lastChangeBlock,
                _getProtocolSwapFeePercentage(),
                change.userData
            )
            : pool.onExitPool(
                poolId,
                sender,
                recipient,
                totalBalances,
                lastChangeBlock,
                _getProtocolSwapFeePercentage(),
                change.userData
            );

        InputHelpers.ensureInputLengthMatch(balances.length, amountsInOrOut.length, dueProtocolFeeAmounts.length);

        finalBalances = kind == PoolBalanceChangeKind.JOIN
            ? _processJoinPoolTransfers(sender, change, balances, amountsInOrOut, dueProtocolFeeAmounts)
            : _processExitPoolTransfers(recipient, change, balances, amountsInOrOut, dueProtocolFeeAmounts);
    }

    function _processJoinPoolTransfers(
        address sender,
        PoolBalanceChange memory change,
        bytes32[] memory balances,
        uint256[] memory amountsIn,
        uint256[] memory dueProtocolFeeAmounts
    ) private returns (bytes32[] memory finalBalances) {
        uint256 wrappedEth = 0;

        finalBalances = new bytes32[](balances.length);
        for (uint256 i = 0; i < change.assets.length; ++i) {
            uint256 amountIn = amountsIn[i];
            _require(amountIn <= change.limits[i], Errors.JOIN_ABOVE_MAX);

            IAsset asset = change.assets[i];
            _receiveAsset(asset, amountIn, sender, change.useInternalBalance);

            if (_isETH(asset)) {
                wrappedEth = wrappedEth.add(amountIn);
            }

            uint256 feeAmount = dueProtocolFeeAmounts[i];
            _payFeeAmount(_translateToIERC20(asset), feeAmount);

            finalBalances[i] = (amountIn >= feeAmount) // This lets us skip checked arithmetic
                ? balances[i].increaseCash(amountIn - feeAmount)
                : balances[i].decreaseCash(feeAmount - amountIn);
        }

        _handleRemainingEth(wrappedEth);
    }

    function _processExitPoolTransfers(
        address payable recipient,
        PoolBalanceChange memory change,
        bytes32[] memory balances,
        uint256[] memory amountsOut,
        uint256[] memory dueProtocolFeeAmounts
    ) private returns (bytes32[] memory finalBalances) {
        finalBalances = new bytes32[](balances.length);
        for (uint256 i = 0; i < change.assets.length; ++i) {
            uint256 amountOut = amountsOut[i];
            _require(amountOut >= change.limits[i], Errors.EXIT_BELOW_MIN);
            IAsset asset = change.assets[i];
            _sendAsset(asset, amountOut, recipient, change.useInternalBalance);

            uint256 feeAmount = dueProtocolFeeAmounts[i];
            _payFeeAmount(_translateToIERC20(asset), feeAmount);
            finalBalances[i] = balances[i].decreaseCash(amountOut.add(feeAmount));
        }
    }
    function _validateTokensAndGetBalances(bytes32 poolId, IERC20[] memory expectedTokens)
        private
        view
        returns (bytes32[] memory)
    {
        (IERC20[] memory actualTokens, bytes32[] memory balances) = _getPoolTokens(poolId);
        InputHelpers.ensureInputLengthMatch(actualTokens.length, expectedTokens.length);
        _require(actualTokens.length > 0, Errors.POOL_NO_TOKENS);

        for (uint256 i = 0; i < actualTokens.length; ++i) {
            _require(actualTokens[i] == expectedTokens[i], Errors.TOKENS_MISMATCH);
        }

        return balances;
    }
    function _unsafeCastToInt256(uint256[] memory values, bool positive)
        private
        pure
        returns (int256[] memory signedValues)
    {
        signedValues = new int256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            signedValues[i] = positive ? int256(values[i]) : -int256(values[i]);
        }
    }
}
