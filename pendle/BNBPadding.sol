// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

abstract contract BNBPadding is Initializable, 
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    uint256[50] private __gap;

    function _BNBPadding_init() public onlyInitializing {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

}