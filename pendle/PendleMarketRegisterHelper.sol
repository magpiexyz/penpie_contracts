// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import { IPendleMarketRegisterHelper } from "../interfaces/pendle/IPendleMarketRegisterHelper.sol";
import { IPMarketFactoryV3 } from "../interfaces/pendle/IPMarketFactoryV3.sol";
import { IPendleStaking } from "../interfaces/IPendleStaking.sol";
import { IPenpieBribeManager } from "../interfaces/IPenpieBribeManager.sol";
import "../interfaces/pendle/IPendleMarket.sol";


/// @title PendlePoolRegisterHelper
/// @author Magpie Team
/// @notice This contract is the main contract that user will intreact with in order to register Pendle Market Lp token on Penpie and also adding it to bribe market.

contract PendleMarketRegisterHelper is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IPendleMarketRegisterHelper
{
    /* ============ State Variables ============ */

    IPendleStaking public pendleStaking;
    address public pendleMarketFactoryV3;
    IPenpieBribeManager public penpieBribeManager;
    uint16 chainId;

    /* ============ Events ============ */

    event NewMarketAdded(address _market, uint256 _allocPoints, string name, string symbol);
    event NewBribePoolAdded(address _market, uint16 _chainId);
    event PendleMarketFactoryV3Set(address _pendleMarketFactoryV3);

    /* ============ Errors ============ */

    error InvalidMarket();
    error InvalidAddress();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __PendleMarketRegisterHelper_init(
        address _pendleStaking,
        address _pendleMarketFactoryV3,
        address _penpieBribeManager,
        uint16 _chainId
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pendleStaking = IPendleStaking(_pendleStaking);
        pendleMarketFactoryV3 = _pendleMarketFactoryV3;
        penpieBribeManager = IPenpieBribeManager(_penpieBribeManager);
        chainId = _chainId;
    }

    /* ============ Modifiers ============ */

    modifier onlyVerifiedMarket(address market) {
        if (!IPMarketFactoryV3(pendleMarketFactoryV3).isValidMarket(market)) revert InvalidMarket();
        _;
    }

    /* ============ External Functions ============ */

    function registerPenpiePool(
        address _market
    ) external {
        _registerMarket(_market, 0);
    }

    function addPenpieBribePool(
        address _market
    ) external {
        _newPool(_market);
    }

    /* ============ Internal Functions ============ */

    function _registerMarket(
        address _market,
        uint256 _allocPoints
    ) internal onlyVerifiedMarket(_market) nonReentrant whenNotPaused {
        (, IPPrincipalToken PT, ) = IPendleMarket(_market).readTokens();
        string memory name = string(abi.encodePacked(PT.symbol(), "-PRT"));
        IPendleStaking(pendleStaking).registerPool(
            _market,
            _allocPoints,
            name,
            name
        );

        emit NewMarketAdded(_market, _allocPoints, name, name);
    }

    function _newPool(
        address _market
    ) internal onlyVerifiedMarket(_market) nonReentrant whenNotPaused {
        IPenpieBribeManager(penpieBribeManager).newPool(
            _market,
            chainId
        );

        emit NewBribePoolAdded(_market, chainId);
    }

    /* ============ Admin Functions ============ */

    function setPendleMarketFactoryV3(address _pendleMarketFactoryV3) external onlyOwner {
        if (_pendleMarketFactoryV3 == address(0)) revert InvalidAddress();
        pendleMarketFactoryV3 = _pendleMarketFactoryV3;

        emit PendleMarketFactoryV3Set(_pendleMarketFactoryV3);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }	

}


