// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IAuthorizer.sol";

import "./VaultAuthorizationMock.sol";
import "./BalancerV2SwapsMock.sol";
import "./AssetHelpersMock.sol";

contract VaultMock is VaultAuthorizationMock, BalancerV2SwapsMock {
    constructor(
        IAuthorizer authorizer,
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    )
        VaultAuthorizationMock(authorizer)
        AssetHelpersMock(weth)
        TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration)
    {
    }

    function setPaused(
        bool paused
    ) external override nonReentrant authenticate {
        _setPaused(paused);
    }

    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view override returns (IWETH) {
        return _WETH();
    }

    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external override {}
}
