// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IAuthorizer.sol";

import "@balancer-labs/v2-solidity-utils/contracts/helpers/Authentication.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/ExtraCalldataEOASignaturesValidator.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/TemporarilyPausable.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";

abstract contract VaultAuthorizationMock is
    IVault,
    ReentrancyGuard,
    Authentication,
    ExtraCalldataEOASignaturesValidator,
    TemporarilyPausable
{
    bytes32 private constant _JOIN_TYPE_HASH = 0x3f7b71252bd19113ff48c19c6e004a9bcfcca320a0d74d58e85877cbd7dcae58;

    bytes32 private constant _EXIT_TYPE_HASH = 0x8bbc57f66ea936902f50a71ce12b92c43f3c5340bb40c27c4e90ab84eeae3353;

    bytes32 private constant _SWAP_TYPE_HASH = 0xe192dcbc143b1e244ad73b813fd3c097b832ad260a157340b4e5e5beda067abe;

    bytes32 private constant _BATCH_SWAP_TYPE_HASH = 0x9bfc43a4d98313c6766986ffd7c916c7481566d9f224c6819af0a53388aced3a;

    bytes32
        private constant _SET_RELAYER_TYPE_HASH = 0xa3f865aa351e51cfeb40f5178d1564bb629fe9030b83caf6361d1baaf5b90b5a;

    IAuthorizer private _authorizer;
    mapping(address => mapping(address => bool)) private _approvedRelayers;

    modifier authenticateFor(address user) {
        _authenticateFor(user);
        _;
    }

    constructor(IAuthorizer authorizer)
        Authentication(bytes32(uint256(address(this))))
        EIP712("Balancer V2 Vault", "1")
    {
        _setAuthorizer(authorizer);
    }

    function setAuthorizer(IAuthorizer newAuthorizer) external override nonReentrant authenticate {
        _setAuthorizer(newAuthorizer);
    }

    function _setAuthorizer(IAuthorizer newAuthorizer) private {
        emit AuthorizerChanged(newAuthorizer);
        _authorizer = newAuthorizer;
    }

    function getAuthorizer() external view override returns (IAuthorizer) {
        return _authorizer;
    }

    function setRelayerApproval(
        address sender,
        address relayer,
        bool approved
    ) external override nonReentrant whenNotPaused authenticateFor(sender) {
        _approvedRelayers[sender][relayer] = approved;
        emit RelayerApprovalChanged(relayer, sender, approved);
    }

    function hasApprovedRelayer(address user, address relayer) external view override returns (bool) {
        return _hasApprovedRelayer(user, relayer);
    }
    function _authenticateFor(address user) internal {
        if (msg.sender != user) {
            _authenticateCaller();

            if (!_hasApprovedRelayer(user, msg.sender)) {
                _validateExtraCalldataSignature(user, Errors.USER_DOESNT_ALLOW_RELAYER);
            }
        }
    }
    function _hasApprovedRelayer(address user, address relayer) internal view returns (bool) {
        return _approvedRelayers[user][relayer];
    }

    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }

    function _entrypointTypeHash() internal pure override returns (bytes32 hash) {
        assembly {
            let selector := shr(224, calldataload(0))

            switch selector
                case 0xb95cac28 {
                    hash := _JOIN_TYPE_HASH
                }
                case 0x8bdb3913 {
                    hash := _EXIT_TYPE_HASH
                }
                case 0x52bbbe29 {
                    hash := _SWAP_TYPE_HASH
                }
                case 0x945bcec9 {
                    hash := _BATCH_SWAP_TYPE_HASH
                }
                case 0xfa6e671d {
                    hash := _SET_RELAYER_TYPE_HASH
                }
                default {
                    hash := 0x0000000000000000000000000000000000000000000000000000000000000000
                }
        }
    }
}
