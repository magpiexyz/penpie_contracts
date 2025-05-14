// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";

import "./ProtocolFeesCollectorMock.sol";
import "./VaultAuthorizationMock.sol";
abstract contract FeesMock is IVault {
    using SafeERC20 for IERC20;

    ProtocolFeesCollectorMock private immutable _protocolFeesCollector;

    constructor() {
        _protocolFeesCollector = new ProtocolFeesCollectorMock(IVault(this));
    }

    function getProtocolFeesCollector() public view override returns (IProtocolFeesCollector) {
        return _protocolFeesCollector;
    }
    function _getProtocolSwapFeePercentage() internal view returns (uint256) {
        return getProtocolFeesCollector().getSwapFeePercentage();
    }
    function _calculateFlashLoanFeeAmount(uint256 amount) internal view returns (uint256) {
        uint256 percentage = getProtocolFeesCollector().getFlashLoanFeePercentage();
        return FixedPoint.mulUp(amount, percentage);
    }

    function _payFeeAmount(IERC20 token, uint256 amount) internal {
        if (amount > 0) {
            token.safeTransfer(address(getProtocolFeesCollector()), amount);
        }
    }
}
