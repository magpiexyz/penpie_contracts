// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { IBatchAddBribe } from "./interfaces/IBatchAddBribe.sol";

contract BatchAddBribeManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    address public penpieBribeManagerContract;
    address public cakepieBribeManagerContract;

    uint256 public constant ADD_BRIBE_TO_PENPIE = 1;
    uint256 public constant ADD_BRIBE_TO_CAKEPIE = 2;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // 1st Upgrade
    address public listapieBribeManagerContract;

    uint256 public constant ADD_BRIBE_TO_LISTAPIE = 3;
    uint256 public constant ADD_BRIBE_TO_THENA = 4;

    address[] public thenaBribePools;
    mapping(address => bool) public isValidthenaBribePool;
    

    /* ============ Events ============ */

    event grantedOperatorRoleTo(address indexed _user);
    event setBribeManagerContractForSubDao(string subDao, address bribeManagerContract);
    event ThenaBribePoolAdded(address pool);

    /* ============ Errors ============ */

    error InvalideArrayLength();
    error InvalideDestination();
    error NotEnoughRewardsInContract();
    error BribeAmountCanNotBeZero();
    error InvalidSubDAO();
    error InvalidThenaPool(address pool);
    error PoolNotAdded(address pool);

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __BatchAddBribeManager_init(
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _grantRole(OPERATOR_ROLE, owner());
    }

    /* ============ External Getters ============ */

    function getThenaBribePools() external view returns (address[] memory) {
        return thenaBribePools;
    }

    /* ============ Write Functions ============ */

    //Note: poolId's will be zero in case of adding bribe to penpie & _pool addresses will be address(0) for listapie
    function batchAddBribeERC20ToTargetTime(
        address[] memory _pool,
        uint256[] memory _poolId,
        address[] memory _token,
        uint256[] memory _amount,
        uint256[] memory _batch,
        uint256[] memory forSubDao,
        bool[] memory forVeToken,
        bool[] memory _forPreviousEpoch
    ) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) {

        if( _token.length != _amount.length ) revert InvalideArrayLength();
        if( _pool.length != _token.length ) revert InvalideArrayLength();
        if( _pool.length != _batch.length ) revert InvalideArrayLength();
        if( _pool.length != forSubDao.length ) revert InvalideArrayLength();
        if( _poolId.length != forSubDao.length ) revert InvalideArrayLength();
        if( _pool.length != forVeToken.length ) revert InvalideArrayLength();
        if( forVeToken.length != _forPreviousEpoch.length ) revert InvalideArrayLength();

        for(uint i = 0;i < _poolId.length; ++i){
            if(_amount[i] == 0) revert BribeAmountCanNotBeZero();
            if(_amount[i] > IERC20(_token[i]).balanceOf(address(this))) revert NotEnoughRewardsInContract();
        }

        for(uint i = 0;i < _poolId.length; ++i)
        {
            if(forSubDao[i] == ADD_BRIBE_TO_PENPIE){
                IERC20(_token[i]).safeApprove(penpieBribeManagerContract, 0);
                IERC20(_token[i]).safeApprove(penpieBribeManagerContract, _amount[i]);

                if(forVeToken[i] == true) {
                    IBatchAddBribe(penpieBribeManagerContract).addBribeERC20ForVePendle(_batch[i], _poolId[i], _token[i], _amount[i], _forPreviousEpoch[i]); 
                } else {
                    IBatchAddBribe(penpieBribeManagerContract).addBribeERC20(_batch[i], _poolId[i], _token[i], _amount[i], _forPreviousEpoch[i]); 
                }
            } else if (forSubDao[i] == ADD_BRIBE_TO_CAKEPIE) {
                IERC20(_token[i]).safeApprove(cakepieBribeManagerContract, 0);
                IERC20(_token[i]).safeApprove(cakepieBribeManagerContract, _amount[i]);
                IBatchAddBribe(cakepieBribeManagerContract).addBribeERC20(_batch[i], _pool[i], _token[i], _amount[i], _forPreviousEpoch[i], forVeToken[i]);

            } else if(forSubDao[i] == ADD_BRIBE_TO_LISTAPIE) {
                uint256 startEpoch = IBatchAddBribe(listapieBribeManagerContract).getCurrentEpoch();
                if(!_forPreviousEpoch[i]) startEpoch = startEpoch + 1;

                IERC20(_token[i]).safeApprove(listapieBribeManagerContract, 0);
                IERC20(_token[i]).safeApprove(listapieBribeManagerContract, _amount[i]);
                IBatchAddBribe(listapieBribeManagerContract).addBribeERC20(uint16(_poolId[i]), _token[i], _amount[i], startEpoch, _batch[i]);

            } else if(forSubDao[i] == ADD_BRIBE_TO_THENA) {
                if(!isValidthenaBribePool[_pool[i]]) revert InvalidThenaPool(_pool[i]);
                IERC20(_token[i]).safeApprove(_pool[i], 0);
                IERC20(_token[i]).safeApprove(_pool[i], _amount[i]);
                IBatchAddBribe(_pool[i]).notifyRewardAmount(_token[i], _amount[i]);
            } else {
                revert InvalideDestination();
            }
        }
    }

    /* ============ Admin Functions ============ */
    
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function grantOperatorRole(address _user, bool grant) external onlyOwner {
        if(grant) {
            _grantRole(OPERATOR_ROLE, _user);
        } else {
            _revokeRole(OPERATOR_ROLE, _user);
        }
        emit grantedOperatorRoleTo(_user);
    }
    
    function setBribeManagerContractOfSubDao(uint256 _subDao, address _bribeManagerContarct) external onlyRole(OPERATOR_ROLE) {
        if(_subDao == ADD_BRIBE_TO_PENPIE)
        {
            penpieBribeManagerContract = _bribeManagerContarct;
            emit setBribeManagerContractForSubDao("PENPIE", _bribeManagerContarct);
        } 
        else if (_subDao == ADD_BRIBE_TO_CAKEPIE)
        {
            cakepieBribeManagerContract = _bribeManagerContarct;
            emit setBribeManagerContractForSubDao("CAKEPIE", _bribeManagerContarct);
        }
        else if(_subDao == ADD_BRIBE_TO_LISTAPIE)
        {
            listapieBribeManagerContract = _bribeManagerContarct;
            emit setBribeManagerContractForSubDao("LISTAPIE", _bribeManagerContarct);
        }
        else
        {
            revert InvalidSubDAO();
        }
    }

    function addThenaBribePool(address _pool) external onlyRole(OPERATOR_ROLE) {
        thenaBribePools.push(_pool);
        isValidthenaBribePool[_pool] = true;

        emit ThenaBribePoolAdded(_pool);
    }

    function removeThenaBribePool(address _pool) external onlyRole(OPERATOR_ROLE) {
        uint256 poolSize = thenaBribePools.length;

        if(!isValidthenaBribePool[_pool]) revert PoolNotAdded(_pool);

        for(uint256 idx = 0; idx < poolSize; idx++) {
            if(thenaBribePools[idx] == _pool) {
                thenaBribePools[idx] = thenaBribePools[poolSize - 1];
                thenaBribePools.pop();
                isValidthenaBribePool[_pool] = false;
                break;
            }
        }
    }

}
