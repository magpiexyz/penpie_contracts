// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/ERC20.sol)
pragma solidity ^0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title The Penpie Recovery Token will be issued to support users affected by the recent Penpie exploit.

/// @author Magpie Team

contract PRT is Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;
    uint8 private _decimals;

    /* ===== 1st upgrade ===== */
    mapping(address => bool) public allowedMinter;
    mapping(address => bool) public allowedBurner;

    /* ============ Errors ============ */
    error OnlyMinter();
    error OnlyBurner();
    /* ============ Events ============ */
    event UpdateMinterStatus(address indexed _user, bool _status);
    event UpdateBurnerStatus(address indexed _user, bool _status);
    /* ============ Modifiers ========= */

    modifier _onlyMinter() {
        if (!allowedMinter[msg.sender]) revert OnlyMinter();
        _;
    }

    modifier _onlyBurner() {
        if (!allowedBurner[msg.sender]) revert OnlyBurner();
        _;
    }

    constructor() {
        _disableInitializers();
    }
    
    function __PRT_init(
        string memory name,
        string memory symbol,
        uint8 _decimal
    ) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init();

        _decimals = _decimal;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external virtual _onlyMinter {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external virtual _onlyBurner {
        _burn(account, amount);
    }

    function updateAllowedMinter(address _user, bool _allowed) external onlyOwner {
        allowedMinter[_user] = _allowed;

        emit UpdateMinterStatus(_user, _allowed);
    }

    function updateAllowedBurner(address _user, bool _allowed) external onlyOwner {
        allowedBurner[_user] = _allowed;

        emit UpdateBurnerStatus(_user, _allowed);
    }
}