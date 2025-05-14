// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeCast.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";

import "./AssetTransfersHandlerMock.sol";
import "./VaultAuthorizationMock.sol";

abstract contract UserBalanceMock is ReentrancyGuard, AssetTransfersHandlerMock, VaultAuthorizationMock {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    mapping(address => mapping(IERC20 => uint256)) private _internalTokenBalance;

    function getInternalBalance(address user, IERC20[] memory tokens)
        external
        view
        override
        returns (uint256[] memory balances)
    {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = _getInternalBalance(user, tokens[i]);
        }
    }

    function manageUserBalance(UserBalanceOp[] memory ops) external payable override nonReentrant {
        uint256 ethWrapped = 0;

        bool checkedCallerIsRelayer = false;
        bool checkedNotPaused = false;

        for (uint256 i = 0; i < ops.length; i++) {
            UserBalanceOpKind kind;
            IAsset asset;
            uint256 amount;
            address sender;
            address payable recipient;

            (kind, asset, amount, sender, recipient, checkedCallerIsRelayer) = _validateUserBalanceOp(
                ops[i],
                checkedCallerIsRelayer
            );

            if (kind == UserBalanceOpKind.WITHDRAW_INTERNAL) {
                _withdrawFromInternalBalance(asset, sender, recipient, amount);
            } else {
                if (!checkedNotPaused) {
                    _ensureNotPaused();
                    checkedNotPaused = true;
                }

                if (kind == UserBalanceOpKind.DEPOSIT_INTERNAL) {
                    _depositToInternalBalance(asset, sender, recipient, amount);

                    if (_isETH(asset)) {
                        ethWrapped = ethWrapped.add(amount);
                    }
                } else {
                    _require(!_isETH(asset), Errors.CANNOT_USE_ETH_SENTINEL);
                    IERC20 token = _asIERC20(asset);

                    if (kind == UserBalanceOpKind.TRANSFER_INTERNAL) {
                        _transferInternalBalance(token, sender, recipient, amount);
                    } else {
                        _transferToExternalBalance(token, sender, recipient, amount);
                    }
                }
            }
        }

        _handleRemainingEth(ethWrapped);
    }

    function _depositToInternalBalance(
        IAsset asset,
        address sender,
        address recipient,
        uint256 amount
    ) private {
        _increaseInternalBalance(recipient, _translateToIERC20(asset), amount);
        _receiveAsset(asset, amount, sender, false);
    }

    function _withdrawFromInternalBalance(
        IAsset asset,
        address sender,
        address payable recipient,
        uint256 amount
    ) private {
        _decreaseInternalBalance(sender, _translateToIERC20(asset), amount, false);
        _sendAsset(asset, amount, recipient, false);
    }

    function _transferInternalBalance(
        IERC20 token,
        address sender,
        address recipient,
        uint256 amount
    ) private {
        _decreaseInternalBalance(sender, token, amount, false);
        _increaseInternalBalance(recipient, token, amount);
    }

    function _transferToExternalBalance(
        IERC20 token,
        address sender,
        address recipient,
        uint256 amount
    ) private {
        if (amount > 0) {
            token.safeTransferFrom(sender, recipient, amount);
            emit ExternalBalanceTransfer(token, sender, recipient, amount);
        }
    }

    function _increaseInternalBalance(
        address account,
        IERC20 token,
        uint256 amount
    ) internal override {
        uint256 currentBalance = _getInternalBalance(account, token);
        uint256 newBalance = currentBalance.add(amount);
        _setInternalBalance(account, token, newBalance, amount.toInt256());
    }

    function _decreaseInternalBalance(
        address account,
        IERC20 token,
        uint256 amount,
        bool allowPartial
    ) internal override returns (uint256 deducted) {
        uint256 currentBalance = _getInternalBalance(account, token);
        _require(allowPartial || (currentBalance >= amount), Errors.INSUFFICIENT_INTERNAL_BALANCE);

        deducted = Math.min(currentBalance, amount);
        uint256 newBalance = currentBalance - deducted;
        _setInternalBalance(account, token, newBalance, -(deducted.toInt256()));
    }
    function _setInternalBalance(
        address account,
        IERC20 token,
        uint256 newBalance,
        int256 delta
    ) private {
        _internalTokenBalance[account][token] = newBalance;
        emit InternalBalanceChanged(account, token, delta);
    }
    function _getInternalBalance(address account, IERC20 token) internal view returns (uint256) {
        return _internalTokenBalance[account][token];
    }

    function _validateUserBalanceOp(UserBalanceOp memory op, bool checkedCallerIsRelayer)
        private
        view
        returns (
            UserBalanceOpKind,
            IAsset,
            uint256,
            address,
            address payable,
            bool
        )
    {
        address sender = op.sender;

        if (sender != msg.sender) {
            if (!checkedCallerIsRelayer) {
                _authenticateCaller();
                checkedCallerIsRelayer = true;
            }

            _require(_hasApprovedRelayer(sender, msg.sender), Errors.USER_DOESNT_ALLOW_RELAYER);
        }

        return (op.kind, op.asset, op.amount, sender, op.recipient, checkedCallerIsRelayer);
    }
}
