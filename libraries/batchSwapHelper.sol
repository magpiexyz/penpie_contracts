// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title batchSwapHelper - batchSwapHelper library
library batchSwapHelper {
    using SafeERC20 for IERC20;
    
    error TransactionDataLengthMismatch();
    error SwapFailed();

    function batchSwap(bytes[] calldata _transactionData, address[] memory _tokensIn, uint256[] memory _amountsIn, address _tokenOut, address _receiver,address odosRouter) internal returns (uint256) {
        if((_transactionData.length != _tokensIn.length) || (_tokensIn.length != _amountsIn.length)) revert TransactionDataLengthMismatch();
        uint256 totalSwappedAmount = 0;

        for (uint256 i = 0; i < _transactionData.length; i++) {
            uint256 swappedAmount = swap(_transactionData[i], _tokensIn[i], _amountsIn[i], _tokenOut, _receiver, odosRouter);
            totalSwappedAmount += swappedAmount;
        }

        return totalSwappedAmount;
    }

    function swap(bytes calldata _transactionData, address _tokenIn, uint256 _amountIn, address _tokenOut, address _receiver, address odosRouter) internal returns (uint256) {
        bytes32 selector;
        assembly {
            selector := calldataload(_transactionData.offset)
        }

        require(bytes4(selector) != IERC20.transferFrom.selector, "Invalid function selector");

        IERC20(_tokenIn).safeApprove(address(odosRouter), _amountIn);
        uint256 initialTokenOutBalance = IERC20(_tokenOut).balanceOf(_receiver);

        (bool success,) = odosRouter.call(_transactionData);
        IERC20(_tokenIn).safeApprove(address(odosRouter), 0);
        
        if (!success) revert SwapFailed();

        uint256 finalTokenOutBalance = IERC20(_tokenOut).balanceOf(_receiver);
        if (finalTokenOutBalance <= initialTokenOutBalance) revert SwapFailed();

        return finalTokenOutBalance - initialTokenOutBalance;
    }
}