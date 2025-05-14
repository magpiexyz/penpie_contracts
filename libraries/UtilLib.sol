// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title UtilLib - Utility library
/// @notice Utility functions
library UtilLib {
    error ZeroAddressNotAllowed();

    /// @dev zero address check modifier
    /// @param address_ address to check
    function checkNonZeroAddress(address address_) internal pure {
        if (address_ == address(0)) revert ZeroAddressNotAllowed();
    }
}