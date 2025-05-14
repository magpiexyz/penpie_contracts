// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import "@balancer-labs/v2-interfaces/contracts/vault/IPoolSwapStructs.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IGeneralPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IMinimalSwapInfoPool.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeCast.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/InputHelpers.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";

import "./PoolBalancesMock.sol";
import "./balances/BalanceAllocationMock.sol";

abstract contract BalancerV2SwapsMock is ReentrancyGuard, PoolBalancesMock {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;

    using Math for int256;
    using Math for uint256;
    using SafeCast for uint256;
    using BalanceAllocationMock for bytes32;

        function swap(
            SingleSwap memory singleSwap,
            FundManagement memory funds,
            uint256 limit,
            uint256 deadline
        )
            external
            payable
            override
            nonReentrant
            whenNotPaused
            authenticateFor(funds.sender)
            returns (uint256 amountCalculated)
    {
        _require(block.timestamp <= deadline, Errors.SWAP_DEADLINE);

        _require(singleSwap.amount > 0, Errors.UNKNOWN_AMOUNT_IN_FIRST_SWAP);

        IERC20 tokenIn = _translateToIERC20(singleSwap.assetIn);
        IERC20 tokenOut = _translateToIERC20(singleSwap.assetOut);
        _require(tokenIn != tokenOut, Errors.CANNOT_SWAP_SAME_TOKEN);

        IPoolSwapStructs.SwapRequest memory poolRequest;
        poolRequest.poolId = singleSwap.poolId;
        poolRequest.kind = singleSwap.kind;
        poolRequest.tokenIn = tokenIn;
        poolRequest.tokenOut = tokenOut;
        poolRequest.amount = singleSwap.amount;
        poolRequest.userData = singleSwap.userData;
        poolRequest.from = funds.sender;
        poolRequest.to = funds.recipient;

        uint256 amountIn;
        uint256 amountOut;

        (amountCalculated, amountIn, amountOut) = _swapWithPool(poolRequest);
        _require(singleSwap.kind == SwapKind.GIVEN_IN ? amountOut >= limit : amountIn <= limit, Errors.SWAP_LIMIT);

        _receiveAsset(singleSwap.assetIn, amountIn, funds.sender, funds.fromInternalBalance);
        _sendAsset(singleSwap.assetOut, amountOut, funds.recipient, funds.toInternalBalance);

        _handleRemainingEth(_isETH(singleSwap.assetIn) ? amountIn : 0);
    }

    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    )
        external
        payable
        override
        nonReentrant
        whenNotPaused
        authenticateFor(funds.sender)
        returns (int256[] memory assetDeltas)
    {
        _require(block.timestamp <= deadline, Errors.SWAP_DEADLINE);

        InputHelpers.ensureInputLengthMatch(assets.length, limits.length);

        assetDeltas = _swapWithPools(swaps, assets, funds, kind);

        uint256 wrappedEth = 0;
        for (uint256 i = 0; i < assets.length; ++i) {
            IAsset asset = assets[i];
            int256 delta = assetDeltas[i];
            _require(delta <= limits[i], Errors.SWAP_LIMIT);

            if (delta > 0) {
                uint256 toReceive = uint256(delta);
                _receiveAsset(asset, toReceive, funds.sender, funds.fromInternalBalance);

                if (_isETH(asset)) {
                    wrappedEth = wrappedEth.add(toReceive);
                }
            } else if (delta < 0) {
                uint256 toSend = uint256(-delta);
                _sendAsset(asset, toSend, funds.recipient, funds.toInternalBalance);
            }
        }

        _handleRemainingEth(wrappedEth);
    }

    function _tokenGiven(
        SwapKind kind,
        IERC20 tokenIn,
        IERC20 tokenOut
    ) private pure returns (IERC20) {
        return kind == SwapKind.GIVEN_IN ? tokenIn : tokenOut;
    }

    function _tokenCalculated(
        SwapKind kind,
        IERC20 tokenIn,
        IERC20 tokenOut
    ) private pure returns (IERC20) {
        return kind == SwapKind.GIVEN_IN ? tokenOut : tokenIn;
    }

    function _getAmounts(
        SwapKind kind,
        uint256 amountGiven,
        uint256 amountCalculated
    ) private pure returns (uint256 amountIn, uint256 amountOut) {
        if (kind == SwapKind.GIVEN_IN) {
            (amountIn, amountOut) = (amountGiven, amountCalculated);
        } else {
            (amountIn, amountOut) = (amountCalculated, amountGiven);
        }
    }

    function _swapWithPools(
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        SwapKind kind
    ) private returns (int256[] memory assetDeltas) {
        assetDeltas = new int256[](assets.length);

        BatchSwapStep memory batchSwapStep;
        IPoolSwapStructs.SwapRequest memory poolRequest;

        IERC20 previousTokenCalculated;
        uint256 previousAmountCalculated;

        for (uint256 i = 0; i < swaps.length; ++i) {
            batchSwapStep = swaps[i];

            bool withinBounds = batchSwapStep.assetInIndex < assets.length &&
                batchSwapStep.assetOutIndex < assets.length;
            _require(withinBounds, Errors.OUT_OF_BOUNDS);

            IERC20 tokenIn = _translateToIERC20(assets[batchSwapStep.assetInIndex]);
            IERC20 tokenOut = _translateToIERC20(assets[batchSwapStep.assetOutIndex]);
            _require(tokenIn != tokenOut, Errors.CANNOT_SWAP_SAME_TOKEN);

            if (batchSwapStep.amount == 0) {
                _require(i > 0, Errors.UNKNOWN_AMOUNT_IN_FIRST_SWAP);
                bool usingPreviousToken = previousTokenCalculated == _tokenGiven(kind, tokenIn, tokenOut);
                _require(usingPreviousToken, Errors.MALCONSTRUCTED_MULTIHOP_SWAP);
                batchSwapStep.amount = previousAmountCalculated;
            }

            poolRequest.poolId = batchSwapStep.poolId;
            poolRequest.kind = kind;
            poolRequest.tokenIn = tokenIn;
            poolRequest.tokenOut = tokenOut;
            poolRequest.amount = batchSwapStep.amount;
            poolRequest.userData = batchSwapStep.userData;
            poolRequest.from = funds.sender;
            poolRequest.to = funds.recipient;

            uint256 amountIn;
            uint256 amountOut;
            (previousAmountCalculated, amountIn, amountOut) = _swapWithPool(poolRequest);

            previousTokenCalculated = _tokenCalculated(kind, tokenIn, tokenOut);

            assetDeltas[batchSwapStep.assetInIndex] = assetDeltas[batchSwapStep.assetInIndex].add(amountIn.toInt256());
            assetDeltas[batchSwapStep.assetOutIndex] = assetDeltas[batchSwapStep.assetOutIndex].sub(
                amountOut.toInt256()
            );
        }
    }

    function _swapWithPool(IPoolSwapStructs.SwapRequest memory request)
        private
        returns (
            uint256 amountCalculated,
            uint256 amountIn,
            uint256 amountOut
        )
    {
        address pool = _getPoolAddress(request.poolId);
        PoolSpecialization specialization = _getPoolSpecialization(request.poolId);

        if (specialization == PoolSpecialization.TWO_TOKEN) {
            amountCalculated = _processTwoTokenPoolSwapRequest(request, IMinimalSwapInfoPool(pool));
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            amountCalculated = _processMinimalSwapInfoPoolSwapRequest(request, IMinimalSwapInfoPool(pool));
        } else {
            amountCalculated = _processGeneralPoolSwapRequest(request, IGeneralPool(pool));
        }

        (amountIn, amountOut) = _getAmounts(request.kind, request.amount, amountCalculated);
        emit Swap(request.poolId, request.tokenIn, request.tokenOut, amountIn, amountOut);
    }

    function _processTwoTokenPoolSwapRequest(IPoolSwapStructs.SwapRequest memory request, IMinimalSwapInfoPool pool)
        private
        returns (uint256 amountCalculated)
    {

        (
            bytes32 tokenABalance,
            bytes32 tokenBBalance,
            TwoTokenPoolBalances storage PoolBalancesMock
        ) = _getTwoTokenPoolSharedBalances(request.poolId, request.tokenIn, request.tokenOut);

        bytes32 tokenInBalance;
        bytes32 tokenOutBalance;

        if (request.tokenIn < request.tokenOut) {
            tokenInBalance = tokenABalance;
            tokenOutBalance = tokenBBalance;
        } else {
            tokenOutBalance = tokenABalance;
            tokenInBalance = tokenBBalance;
        }

        (tokenInBalance, tokenOutBalance, amountCalculated) = _callMinimalSwapInfoPoolOnSwapHook(
            request,
            pool,
            tokenInBalance,
            tokenOutBalance
        );

        PoolBalancesMock.sharedCash = request.tokenIn < request.tokenOut
            ? BalanceAllocationMock.toSharedCash(tokenInBalance, tokenOutBalance) // in is A, out is B
            : BalanceAllocationMock.toSharedCash(tokenOutBalance, tokenInBalance); // in is B, out is A
    }

    function _processMinimalSwapInfoPoolSwapRequest(
        IPoolSwapStructs.SwapRequest memory request,
        IMinimalSwapInfoPool pool
    ) private returns (uint256 amountCalculated) {
        bytes32 tokenInBalance = _getMinimalSwapInfoPoolBalance(request.poolId, request.tokenIn);
        bytes32 tokenOutBalance = _getMinimalSwapInfoPoolBalance(request.poolId, request.tokenOut);

        (tokenInBalance, tokenOutBalance, amountCalculated) = _callMinimalSwapInfoPoolOnSwapHook(
            request,
            pool,
            tokenInBalance,
            tokenOutBalance
        );

        _minimalSwapInfoPoolsBalances[request.poolId][request.tokenIn] = tokenInBalance;
        _minimalSwapInfoPoolsBalances[request.poolId][request.tokenOut] = tokenOutBalance;
    }

    function _callMinimalSwapInfoPoolOnSwapHook(
        IPoolSwapStructs.SwapRequest memory request,
        IMinimalSwapInfoPool pool,
        bytes32 tokenInBalance,
        bytes32 tokenOutBalance
    )
        internal
        returns (
            bytes32 newTokenInBalance,
            bytes32 newTokenOutBalance,
            uint256 amountCalculated
        )
    {
        uint256 tokenInTotal = tokenInBalance.total();
        uint256 tokenOutTotal = tokenOutBalance.total();
        request.lastChangeBlock = Math.max(tokenInBalance.lastChangeBlock(), tokenOutBalance.lastChangeBlock());

        amountCalculated = pool.onSwap(request, tokenInTotal, tokenOutTotal);
        (uint256 amountIn, uint256 amountOut) = _getAmounts(request.kind, request.amount, amountCalculated);

        newTokenInBalance = tokenInBalance.increaseCash(amountIn);
        newTokenOutBalance = tokenOutBalance.decreaseCash(amountOut);
    }

    function _processGeneralPoolSwapRequest(IPoolSwapStructs.SwapRequest memory request, IGeneralPool pool)
        private
        returns (uint256 amountCalculated)
    {
        bytes32 tokenInBalance;
        bytes32 tokenOutBalance;

        EnumerableMap.IERC20ToBytes32Map storage PoolBalancesMock = _generalPoolsBalances[request.poolId];
        uint256 indexIn = PoolBalancesMock.unchecked_indexOf(request.tokenIn);
        uint256 indexOut = PoolBalancesMock.unchecked_indexOf(request.tokenOut);

        if (indexIn == 0 || indexOut == 0) {
            _ensureRegisteredPool(request.poolId);
            _revert(Errors.TOKEN_NOT_REGISTERED);
        }

        indexIn -= 1;
        indexOut -= 1;

        uint256 tokenAmount = PoolBalancesMock.length();
        uint256[] memory currentBalances = new uint256[](tokenAmount);

        request.lastChangeBlock = 0;
        for (uint256 i = 0; i < tokenAmount; i++) {
            bytes32 balance = PoolBalancesMock.unchecked_valueAt(i);

            currentBalances[i] = balance.total();
            request.lastChangeBlock = Math.max(request.lastChangeBlock, balance.lastChangeBlock());

            if (i == indexIn) {
                tokenInBalance = balance;
            } else if (i == indexOut) {
                tokenOutBalance = balance;
            }
        }

        amountCalculated = pool.onSwap(request, currentBalances, indexIn, indexOut);
        (uint256 amountIn, uint256 amountOut) = _getAmounts(request.kind, request.amount, amountCalculated);
        tokenInBalance = tokenInBalance.increaseCash(amountIn);
        tokenOutBalance = tokenOutBalance.decreaseCash(amountOut);
        PoolBalancesMock.unchecked_setAt(indexIn, tokenInBalance);
        PoolBalancesMock.unchecked_setAt(indexOut, tokenOutBalance);
    }

    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds
    ) external override returns (int256[] memory) {

        if (msg.sender != address(this)) {

            (bool success, ) = address(this).call(msg.data);

            assembly {
                switch success
                    case 0 {
                        returndatacopy(0, 0, 0x04)
                        let error := and(mload(0), 0xffffffff00000000000000000000000000000000000000000000000000000000)

                        if eq(eq(error, 0xfa61cc1200000000000000000000000000000000000000000000000000000000), 0) {
                            returndatacopy(0, 0, returndatasize())
                            revert(0, returndatasize())
                        }

                        mstore(0, 32)
                        let size := sub(returndatasize(), 0x04)
                        returndatacopy(0x20, 0x04, size)
                        return(0, add(size, 32))
                    }
                    default {
                        invalid()
                    }
            }
        } else {
            int256[] memory deltas = _swapWithPools(swaps, assets, funds, kind);

            assembly {
                let size := mul(mload(deltas), 32)

                mstore(sub(deltas, 0x20), 0x00000000000000000000000000000000000000000000000000000000fa61cc12)
                let start := sub(deltas, 0x04)

                revert(start, add(size, 36))
            }
        }
    }
}
