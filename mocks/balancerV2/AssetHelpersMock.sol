// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";

abstract contract AssetHelpersMock {
    IWETH private immutable _weth;

    address private constant _ETH = address(0);

    constructor(IWETH weth) {
        _weth = weth;
    }

    function _WETH() internal view returns (IWETH) {
        return _weth;
    }

    function _isETH(IAsset asset) internal pure returns (bool) {
        return address(asset) == _ETH;
    }
    function _translateToIERC20(IAsset asset) internal view returns (IERC20) {
        return _isETH(asset) ? _WETH() : _asIERC20(asset);
    }
    function _translateToIERC20(IAsset[] memory assets) internal view returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](assets.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            tokens[i] = _translateToIERC20(assets[i]);
        }
        return tokens;
    }
    function _asIERC20(IAsset asset) internal pure returns (IERC20) {
        return IERC20(address(asset));
    }
}
