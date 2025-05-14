// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Address.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";

import "./AssetHelpersMock.sol";

abstract contract AssetTransfersHandlerMock is AssetHelpersMock {
    using SafeERC20 for IERC20;
    using Address for address payable;

    function _receiveAsset(
        IAsset asset,
        uint256 amount,
        address sender,
        bool fromInternalBalance
    ) internal {
        if (amount == 0) {
            return;
        }

        if (_isETH(asset)) {
            _require(!fromInternalBalance, Errors.INVALID_ETH_INTERNAL_BALANCE);
            _require(address(this).balance >= amount, Errors.INSUFFICIENT_ETH);
            _WETH().deposit{ value: amount }();
        } else {
            IERC20 token = _asIERC20(asset);

            if (fromInternalBalance) {
                uint256 deductedBalance = _decreaseInternalBalance(sender, token, amount, true);
                amount -= deductedBalance;
            }

            if (amount > 0) {
                token.safeTransferFrom(sender, address(this), amount);
            }
        }
    }
    function _sendAsset(
        IAsset asset,
        uint256 amount,
        address payable recipient,
        bool toInternalBalance
    ) internal {
        if (amount == 0) {
            return;
        }

        if (_isETH(asset)) {
            _require(!toInternalBalance, Errors.INVALID_ETH_INTERNAL_BALANCE);
            _WETH().withdraw(amount);
            recipient.sendValue(amount);
        } else {
            IERC20 token = _asIERC20(asset);
            if (toInternalBalance) {
                _increaseInternalBalance(recipient, token, amount);
            } else {
                token.safeTransfer(recipient, amount);
            }
        }
    }
    function _handleRemainingEth(uint256 amountUsed) internal {
        _require(msg.value >= amountUsed, Errors.INSUFFICIENT_ETH);

        uint256 excess = msg.value - amountUsed;
        if (excess > 0) {
            msg.sender.sendValue(excess);
        }
    }
    receive() external payable {
        _require(msg.sender == address(_WETH()), Errors.ETH_TRANSFER);
    }

    function _increaseInternalBalance(
        address account,
        IERC20 token,
        uint256 amount
    ) internal virtual;

    function _decreaseInternalBalance(
        address account,
        IERC20 token,
        uint256 amount,
        bool capped
    ) internal virtual returns (uint256);
}
