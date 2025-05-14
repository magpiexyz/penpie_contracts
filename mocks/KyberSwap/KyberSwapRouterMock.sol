// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

library Address {
   
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        // return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint256);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// File: contracts/libraries/RevertReasonParser.sol

library RevertReasonParser {
  function parse(bytes memory data, string memory prefix) internal pure returns (string memory) {
    if (data.length >= 68 && data[0] == '\x08' && data[1] == '\xc3' && data[2] == '\x79' && data[3] == '\xa0') {
      string memory reason;
      assembly {
        reason := add(data, 68)
      }
      require(data.length >= 68 + bytes(reason).length, 'Invalid revert reason');
      return string(abi.encodePacked(prefix, 'Error(', reason, ')'));
    }
    else if (data.length == 36 && data[0] == '\x4e' && data[1] == '\x48' && data[2] == '\x7b' && data[3] == '\x71') {
      uint256 code;
      assembly {
        code := mload(add(data, 36))
      }
      return string(abi.encodePacked(prefix, 'Panic(', _toHex(code), ')'));
    }

    return string(abi.encodePacked(prefix, 'Unknown(', _toHex(data), ')'));
  }

  function _toHex(uint256 value) private pure returns (string memory) {
    return _toHex(abi.encodePacked(value));
  }

  function _toHex(bytes memory data) private pure returns (string memory) {
    bytes16 alphabet = 0x30313233343536373839616263646566;
    bytes memory str = new bytes(2 + data.length * 2);
    str[0] = '0';
    str[1] = 'x';
    for (uint256 i = 0; i < data.length; i++) {
      str[2 * i + 2] = alphabet[uint8(data[i] >> 4)];
      str[2 * i + 3] = alphabet[uint8(data[i] & 0x0f)];
    }
    return string(str);
  }
}

contract Permitable {
  event Error(string reason);

  function _permit(
    IERC20 token,
    uint256 amount,
    bytes memory permit
  ) internal {
    if (permit.length == 32 * 7) {
      // solhint-disable-next-line avoid-low-level-calls
      (bool success, bytes memory result) = address(token).call(
        abi.encodePacked(IERC20Permit.permit.selector, permit)
      );
      if (!success) {
        string memory reason = RevertReasonParser.parse(result, 'Permit call failed: ');
        if (token.allowance(msg.sender, address(this)) < amount) {
          revert(reason);
        } else {
          emit Error(reason);
        }
      }
    }
  }
}

interface IAggregationExecutor {
  function callBytes(bytes calldata data) external payable; // 0xd9c45357

  function swapSingleSequence(bytes calldata data) external;

  function finalTransactionProcessing(
    address tokenIn,
    address tokenOut,
    address to,
    bytes calldata destTokenFeeData
  ) external;
}

interface IAggregationExecutor1Inch {
  function callBytes(address msgSender, bytes calldata data) external payable; // 0x2636f7f8
}

interface IAggregationRouter1InchV4 {
  function swap(
    IAggregationExecutor1Inch caller,
    SwapDescription1Inch calldata desc,
    bytes calldata data
  ) external payable returns (uint256 returnAmount, uint256 gasLeft);
}

struct SwapDescription1Inch {
  IERC20 srcToken;
  IERC20 dstToken;
  address payable srcReceiver;
  address payable dstReceiver;
  uint256 amount;
  uint256 minReturnAmount;
  uint256 flags;
  bytes permit;
}

struct SwapDescriptionExecutor1Inch {
  IERC20 srcToken;
  IERC20 dstToken;
  address payable srcReceiver1Inch;
  address payable dstReceiver;
  address[] srcReceivers;
  uint256[] srcAmounts;
  uint256 amount;
  uint256 minReturnAmount;
  uint256 flags;
  bytes permit;
}

// File: contracts/libraries/TransferHelper.sol

library TransferHelper {
  function safeApprove(
    address token,
    address to,
    uint256 value
  ) internal {
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
  }

  function safeTransfer(
    address token,
    address to,
    uint256 value
  ) internal {
    if (value == 0) return;
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
  }

  function safeTransferFrom(
    address token,
    address from,
    address to,
    uint256 value
  ) internal {
    if (value == 0) return;
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
  }

  function safeTransferETH(address to, uint256 value) internal {
    if (value == 0) return;
    (bool success, ) = to.call{value: value}(new bytes(0));
    require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
  }
}

contract kyBarSwapRouter is Permitable, Ownable {
  using SafeERC20 for IERC20;

  address public immutable WETH;
  address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

  uint256 private constant _PARTIAL_FILL = 0x01;
  uint256 private constant _REQUIRES_EXTRA_ETH = 0x02;
  uint256 private constant _SHOULD_CLAIM = 0x04;
  uint256 private constant _BURN_FROM_MSG_SENDER = 0x08;
  uint256 private constant _BURN_FROM_TX_ORIGIN = 0x10;
  uint256 private constant _SIMPLE_SWAP = 0x20;
  uint256 private constant _FEE_ON_DST = 0x40;
  uint256 private constant _FEE_IN_BPS = 0x80;
  uint256 private constant _APPROVE_FUND = 0x100;

  uint256 private constant BPS = 10000;

  mapping(address => bool) public isWhitelist;

  struct SwapDescriptionV2 {
    IERC20 srcToken;
    IERC20 dstToken;
    address[] srcReceivers; // transfer src token to these addresses, default
    uint256[] srcAmounts;
    address[] feeReceivers;
    uint256[] feeAmounts;
    address dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
  }

  /// @dev  use for swapGeneric and swap to avoid stack too deep
  struct SwapExecutionParams {
    address callTarget; // call this address
    address approveTarget; // approve this address if _APPROVE_FUND set
    bytes targetData;
    SwapDescriptionV2 desc;
    bytes clientData;
  }

  struct SimpleSwapData {
    address[] firstPools;
    uint256[] firstSwapAmounts;
    bytes[] swapDatas;
    uint256 deadline;
    bytes destTokenFeeData;
  }

  event Swapped(
    address sender,
    IERC20 srcToken,
    IERC20 dstToken,
    address dstReceiver,
    uint256 spentAmount,
    uint256 returnAmount
  );

  event ClientData(bytes clientData);

  event Exchange(address pair, uint256 amountOut, address output);

  event Fee(address token, uint256 totalAmount, uint256 totalFee, address[] recipients, uint256[] amounts, bool isBps);

  constructor(address _WETH) {
    WETH = _WETH;
  }

  receive() external payable {}

  function rescueFunds(address token, uint256 amount) external onlyOwner {
    if (_isETH(IERC20(token))) {
      TransferHelper.safeTransferETH(msg.sender, amount);
    } else {
      TransferHelper.safeTransfer(token, msg.sender, amount);
    }
  }

  function updateWhitelist(address[] memory addr, bool[] memory value) external onlyOwner {
    require(addr.length == value.length);
    for (uint256 i; i < addr.length; ++i) {
      isWhitelist[addr[i]] = value[i];
    }
  }

  function swapGeneric(SwapExecutionParams calldata execution)
    external
    payable
    returns (uint256 returnAmount, uint256 gasUsed)
  {
    uint256 gasBefore = gasleft();
    require(isWhitelist[execution.callTarget], 'Address not whitelisted');
    if (execution.approveTarget != execution.callTarget && execution.approveTarget != address(0)) {
      require(isWhitelist[execution.approveTarget], 'Address not whitelisted');
    }
    SwapDescriptionV2 memory desc = execution.desc;
    require(desc.minReturnAmount > 0, 'Invalid min return amount');

    // if extra eth is needed, in case srcToken is ETH
    _collectExtraETHIfNeeded(desc);
    _permit(desc.srcToken, desc.amount, desc.permit);

    bool feeInBps = _flagsChecked(desc.flags, _FEE_IN_BPS);
    uint256 spentAmount;
    address dstReceiver = desc.dstReceiver == address(0) ? msg.sender : desc.dstReceiver;
    if (!_flagsChecked(desc.flags, _FEE_ON_DST)) {
      // fee on src token
      // take fee on srcToken

      // take fee and deduct total amount
      desc.amount = _takeFee(desc.srcToken, msg.sender, desc.feeReceivers, desc.feeAmounts, desc.amount, feeInBps);

      bool collected;
      if (!_isETH(desc.srcToken) && _flagsChecked(desc.flags, _SHOULD_CLAIM)) {
        (collected, desc.amount) = _collectTokenIfNeeded(desc, msg.sender, address(this));
      }

      _transferFromOrApproveTarget(msg.sender, execution.approveTarget, desc, collected);
      // execute swap
      (spentAmount, returnAmount) = _executeSwap(
        execution.callTarget,
        execution.targetData,
        desc,
        _isETH(desc.srcToken) ? desc.amount : 0,
        dstReceiver
      );
    } else {
      bool collected;
      if (!_isETH(desc.srcToken) && _flagsChecked(desc.flags, _SHOULD_CLAIM)) {
        (collected, desc.amount) = _collectTokenIfNeeded(desc, msg.sender, address(this));
      }

      uint256 initialDstReceiverBalance = _getBalance(desc.dstToken, dstReceiver);
      _transferFromOrApproveTarget(msg.sender, execution.approveTarget, desc, collected);
      // fee on dst token
      // router get dst token first
      (spentAmount, returnAmount) = _executeSwap(
        execution.callTarget,
        execution.targetData,
        desc,
        _isETH(desc.srcToken) ? msg.value : 0,
        address(this)
      );
      {
        // then take fee on dst token
        uint256 leftAmount = _takeFee(
          desc.dstToken,
          address(this),
          desc.feeReceivers,
          desc.feeAmounts,
          returnAmount,
          feeInBps
        );
        _doTransferERC20(desc.dstToken, address(this), dstReceiver, leftAmount);
      }

      returnAmount = _getBalance(desc.dstToken, dstReceiver) - initialDstReceiverBalance;
    }
    // check return amount
    _checkReturnAmount(spentAmount, returnAmount, desc);
    //revoke allowance
    if (!_isETH(desc.srcToken) && execution.approveTarget != address(0)) {
      desc.srcToken.safeApprove(execution.approveTarget, 0);
    }

    emit Swapped(msg.sender, desc.srcToken, desc.dstToken, dstReceiver, spentAmount, returnAmount);
    emit Exchange(execution.callTarget, returnAmount, _isETH(desc.dstToken) ? WETH : address(desc.dstToken));
    emit ClientData(execution.clientData);
    unchecked {
      gasUsed = gasBefore - gasleft();
    }
  }

  function _doTransferERC20(
    IERC20 token,
    address from,
    address to,
    uint256 amount
  ) internal {
    require(from != to, 'sender != recipient');
    if (amount > 0) {
      if (_isETH(token)) {
        if (from == address(this)) TransferHelper.safeTransferETH(to, amount);
      } else {
        if (from == address(this)) {
          TransferHelper.safeTransfer(address(token), to, amount);
        } else {
          TransferHelper.safeTransferFrom(address(token), from, to, amount);
        }
      }
    }
  }

  // Only use this mode if the first pool of each sequence can receive tokenIn directly into the pool
  function _swapMultiSequencesWithSimpleMode(
    IAggregationExecutor caller,
    address tokenIn,
    uint256 totalSwapAmount,
    address tokenOut,
    address dstReceiver,
    bytes calldata data
  ) internal {
    SimpleSwapData memory swapData = abi.decode(data, (SimpleSwapData));
    require(swapData.deadline >= block.timestamp, 'ROUTER: Expired');
    require(
      swapData.firstPools.length == swapData.firstSwapAmounts.length &&
        swapData.firstPools.length == swapData.swapDatas.length,
      'invalid swap data length'
    );
    uint256 numberSeq = swapData.firstPools.length;
    for (uint256 i = 0; i < numberSeq; i++) {
      // collect amount to the first pool
      {
        uint256 balanceBefore = _getBalance(IERC20(tokenIn), msg.sender);
        _doTransferERC20(IERC20(tokenIn), msg.sender, swapData.firstPools[i], swapData.firstSwapAmounts[i]);
        require(swapData.firstSwapAmounts[i] <= totalSwapAmount, 'invalid swap amount');
        uint256 spentAmount = balanceBefore - _getBalance(IERC20(tokenIn), msg.sender);
        totalSwapAmount -= spentAmount;
      }
      {
        // solhint-disable-next-line avoid-low-level-calls
        // may take some native tokens for commission fee
        (bool success, bytes memory result) = address(caller).call(
          abi.encodeWithSelector(caller.swapSingleSequence.selector, swapData.swapDatas[i])
        );
        if (!success) {
          revert(RevertReasonParser.parse(result, 'swapSingleSequence failed: '));
        }
      }
    }
    {
      // solhint-disable-next-line avoid-low-level-calls
      // may take some native tokens for commission fee
      (bool success, bytes memory result) = address(caller).call(
        abi.encodeWithSelector(
          caller.finalTransactionProcessing.selector,
          tokenIn,
          tokenOut,
          dstReceiver,
          swapData.destTokenFeeData
        )
      );
      if (!success) {
        revert(RevertReasonParser.parse(result, 'finalTransactionProcessing failed: '));
      }
    }
  }

  function _getBalance(IERC20 token, address account) internal view returns (uint256) {
    if (_isETH(token)) {
      return account.balance;
    } else {
      return token.balanceOf(account);
    }
  }

  function _isETH(IERC20 token) internal pure returns (bool) {
    return (address(token) == ETH_ADDRESS);
  }

  /// @dev this function calls to external contract to execute swap and also validate the returned amounts
  function _executeSwap(
    address callTarget,
    bytes memory targetData,
    SwapDescriptionV2 memory desc,
    uint256 value,
    address dstReceiver
  ) internal returns (uint256 spentAmount, uint256 returnAmount) {
    uint256 initialDstBalance = _getBalance(desc.dstToken, dstReceiver);
    uint256 routerInitialSrcBalance = _getBalance(desc.srcToken, address(this));
    uint256 routerInitialDstBalance = _getBalance(desc.dstToken, address(this));
    {
      // call to external contract
      (bool success, ) = callTarget.call{value: value}(targetData);
      require(success, 'Call failed');
    }

    // if the `callTarget` returns amount to `msg.sender`, meaning this contract
    if (dstReceiver != address(this)) {
      uint256 stuckAmount = _getBalance(desc.dstToken, address(this)) - routerInitialDstBalance;
      _doTransferERC20(desc.dstToken, address(this), dstReceiver, stuckAmount);
    }

    // safe check here
    returnAmount = _getBalance(desc.dstToken, dstReceiver) - initialDstBalance;
    spentAmount = desc.amount;

    //should refund tokens router collected when partial fill
    if (
      _flagsChecked(desc.flags, _PARTIAL_FILL) && (_isETH(desc.srcToken) || _flagsChecked(desc.flags, _SHOULD_CLAIM))
    ) {
      uint256 currBalance = _getBalance(desc.srcToken, address(this));
      if (currBalance != routerInitialSrcBalance) {
        spentAmount = routerInitialSrcBalance - currBalance;
        _doTransferERC20(desc.srcToken, address(this), msg.sender, desc.amount - spentAmount);
      }
    }
  }

  function _collectExtraETHIfNeeded(SwapDescriptionV2 memory desc) internal {
    bool srcETH = _isETH(desc.srcToken);
    if (_flagsChecked(desc.flags, _REQUIRES_EXTRA_ETH)) {
      require(msg.value > (srcETH ? desc.amount : 0), 'Invalid msg.value');
    } else {
      require(msg.value == (srcETH ? desc.amount : 0), 'Invalid msg.value');
    }
  }

  function _collectTokenIfNeeded(
    SwapDescriptionV2 memory desc,
    address from,
    address to
  ) internal returns (bool collected, uint256 amount) {
    require(!_isETH(desc.srcToken), 'Claim token is ETH');
    uint256 initialRouterSrcBalance = _getBalance(desc.srcToken, address(this));
    _doTransferERC20(desc.srcToken, from, to, desc.amount);
    collected = true;
    amount = _getBalance(desc.srcToken, address(this)) - initialRouterSrcBalance;
  }

  /// @dev transfer fund to `callTarget` or approve `approveTarget`
  function _transferFromOrApproveTarget(
    address from,
    address approveTarget,
    SwapDescriptionV2 memory desc,
    bool collected
  ) internal {
    // if token is collected
    require(desc.srcReceivers.length == desc.srcAmounts.length, 'invalid srcReceivers length');
    if (collected) {
      if (_flagsChecked(desc.flags, _APPROVE_FUND) && approveTarget != address(0)) {
        // approve to approveTarget since some systems use an allowance proxy contract
        desc.srcToken.safeIncreaseAllowance(approveTarget, desc.amount);
        return;
      }
    }
    uint256 total;
    for (uint256 i; i < desc.srcReceivers.length; ++i) {
      total += desc.srcAmounts[i];
      _doTransferERC20(desc.srcToken, collected ? address(this) : from, desc.srcReceivers[i], desc.srcAmounts[i]);
    }
    require(total <= desc.amount, 'Exceeded desc.amount');
  }

  /// @dev token transferred from `from` to `feeData.recipients`
  function _takeFee(
    IERC20 token,
    address from,
    address[] memory recipients,
    uint256[] memory amounts,
    uint256 totalAmount,
    bool inBps
  ) internal returns (uint256 leftAmount) {
    leftAmount = totalAmount;
    uint256 recipientsLen = recipients.length;
    if (recipientsLen > 0) {
      bool isETH = _isETH(token);
      uint256 balanceBefore = _getBalance(token, isETH ? address(this) : from);
      require(amounts.length == recipientsLen, 'Invalid length');
      for (uint256 i; i < recipientsLen; ++i) {
        uint256 amount = inBps ? (totalAmount * amounts[i]) / BPS : amounts[i];
        _doTransferERC20(token, isETH ? address(this) : from, recipients[i], amount);
      }
      uint256 totalFee = balanceBefore - _getBalance(token, isETH ? address(this) : from);
      leftAmount = totalAmount - totalFee;
      emit Fee(address(token), totalAmount, totalFee, recipients, amounts, inBps);
    }
  }

  function _checkReturnAmount(
    uint256 spentAmount,
    uint256 returnAmount,
    SwapDescriptionV2 memory desc
  ) internal pure {
    if (_flagsChecked(desc.flags, _PARTIAL_FILL)) {
      require(returnAmount * desc.amount >= desc.minReturnAmount * spentAmount, 'Return amount is not enough');
    } else {
      require(returnAmount >= desc.minReturnAmount, 'Return amount is not enough');
    }
  }

  function _flagsChecked(uint256 number, uint256 flag) internal pure returns (bool) {
    return number & flag != 0;
  }
}