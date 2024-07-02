// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './OlympexCommon.sol';
import './UniswapV3Exchange.sol';
import './UniswapV2Aggregator.sol';
import './libraries/UniversalERC20.sol';
import './interfaces/IOlympexMessenger.sol';
import './libraries/RevertReasonParser.sol';
import './interfaces/IOlympexAggregator.sol';
import './interfaces/IOlympexCommon.sol';

contract OlympexAggregator is
	IOlympexAggregator,
	OwnableUpgradeable,
	PausableUpgradeable,
	OlympexCommon,
	UniswapV2Aggregator,
	UniswapV3Exchange,
	UUPSUpgradeable
{
	using SafeERC20 for IERC20;
	using UniversalERC20 for IERC20;

	using ECDSA for bytes32;
	using MessageHashUtils for bytes32;

	/********
	 * INDEX *
	 *********/
	// 1. Type declarations.
	// 2. Constants and variables.
	// 3. Events.
	// 4. Functions.

	/***********************
	 * 1. TYPE DECLARATIONS *
	 ************************/
	// empty

	/*****************************
	 * 2. CONSTANTS AND VARIABLES *
	 ******************************/
	/// @dev Define what is the minimum traded volume required to mint Olympex NFTs.
	uint256 public minTradeVolume;

	/**
	 * @dev It is used as a flag to determine whether a partial fill should be performed or
	 * not, depending on whether a native token or an ERC20 token is swapped as an input token
	 **/
	uint256 private constant _PARTIAL_FILL = 0x01;

	/**
	 * @dev It is used as an indicator to determine whether to claim an ERC20 token that
	 * implements approvals through signatures
	 **/
	uint256 private constant _SHOULD_CLAIM = 0x02;

	/**************
	 * 3. Events *
	 ***************/
	// empty

	/***************
	 * 4. FUNCTIONS *
	 ****************/
	/**
	 * @dev Initializes the OlympexAggregator contract during deployment
	 * @param feeCollector_ Address of the fee collector
	 * @param minTradeVolume_ Minimum traded volume required to mint Olympex NFTs
	 * @param signerAddress_ Wallet address authorized to sign backend transactions
	 **/
	function initialize(
		address feeCollector_,
		uint256 minTradeVolume_,
		address signerAddress_
	) external initializer {
		__Ownable_init(msg.sender);
		__Pausable_init();
		__UUPSUpgradeable_init();
		__UniswapV2Aggregator_init(feeCollector_, signerAddress_);

		minTradeVolume = minTradeVolume_;
	}

	function rescueFunds(IERC20 token_, uint256 amount_) external onlyOwner {
		token_.universalTransfer(payable(msg.sender), amount_);
	}

	function setMinTradeVolume(uint256 minTradeVolume_) external onlyOwner {
		minTradeVolume = minTradeVolume_;
	}

	function pause() external onlyOwner {
		_pause();
	}

	/**
	 * @dev Executes a token swap operation, allowing users to exchange tokens on Olympex
	 * @param hermes_ IOlympexMessenger contract facilitating off-chain communication
	 * @param desc_ SwapDescription struct containing swap details and parameters
	 * @param messengers_ Array of MessageDescriptions for interacting with external protocols
	 * @return returnAmount_ The amount of destination tokens received after the swap
	 **/
	function swap(
		IOlympexMessenger hermes_,
		IOlympexCommon.SwapDescription calldata desc_,
		IOlympexMessenger.MessageDescription[] calldata messengers_
	) external payable whenNotPaused returns (uint256 returnAmount_) {
		require(desc_.minReturnAmount > 0, 'Min return should not be 0');
		require(messengers_.length > 0, 'Call data should exist');

		uint256 flags = desc_.flags;
		IERC20 srcToken = desc_.srcToken;
		IERC20 dstToken = desc_.dstToken;

		require(msg.value == (srcToken.isETH() ? desc_.amount : 0), 'Invalid msg.value');
		
		if (flags & _SHOULD_CLAIM != 0) {
			require(!srcToken.isETH(), 'Claim token is ETH');
			_claim(srcToken, desc_.srcReceiver, desc_.amount);
		}

		address dstReceiver = (desc_.dstReceiver == address(0))
			? msg.sender
			: desc_.dstReceiver;

		uint256 initialSrcBalance = (flags & _PARTIAL_FILL != 0)
			? srcToken.universalBalanceOf(msg.sender)
			: 0;

		uint256 tradedVolume = desc_.tradedVolume;

		require(
			verifySignerTradedVolume(
				desc_.amount,
				tradedVolume,
				srcToken,
				dstToken,
				dstReceiver,
				desc_.signature
			),
			'Invalid tradedVolume'
		);

		uint256 initialDstBalance = dstToken.universalBalanceOf(dstReceiver);

		hermes_.makeCalls{ value: msg.value }(messengers_);

		uint256 spentAmount = desc_.amount;
		returnAmount_ = dstToken.universalBalanceOf(dstReceiver) - initialDstBalance;

		if (flags & _PARTIAL_FILL != 0) {
			spentAmount =
				initialSrcBalance +
				desc_.amount -
				srcToken.universalBalanceOf(msg.sender);
			require(
				returnAmount_ * desc_.amount >= desc_.minReturnAmount * spentAmount,
				'Return amount is not enough'
			);
		} else {
			require(returnAmount_ >= desc_.minReturnAmount, 'Return amount is not enough');
		}

		tradingVolume[dstReceiver] += tradedVolume;

		_emitSwapped(desc_, dstReceiver, spentAmount, returnAmount_);
	}

	function _authorizeUpgrade(address) internal override onlyOwner {}

	/**
	 * @dev Internal function to emit the Swapped event with detailed swap information.
	 * This function emits the Swapped event, providing a concise way to log detailed
	 * information about a successful token swap. It helps avoid the "Stack too deep" error
	 * by directly passing individual parameters instead of local variables within the event
	 * @param desc_ SwapDescription struct containing swap details and parameters
	 * @param dstReceiver_ Address receiving the destination tokens
	 * @param spentAmount_ Total amount spent during the swap (source tokens + fees)
	 * @param returnAmount_ Amount of destination tokens received in the swap
	 **/
	function _emitSwapped(
		IOlympexCommon.SwapDescription calldata desc_,
		address dstReceiver_,
		uint256 spentAmount_,
		uint256 returnAmount_
	) private {
		emit Swapped(
			dstReceiver_,
			desc_.srcToken,
			desc_.dstToken,
			desc_.tradedVolume,
			spentAmount_,
			returnAmount_,
			desc_.nftPoints,
			desc_.tokenId,
			desc_.nftType
		);
	}

	/**
	 * @dev Internal function to claim tokens and transfer them to a specified address.
	 * @param token_ The ERC20 token to be claimed and transferred
	 * @param dst_ The destination address where the tokens will be transferred
	 * @param amount_ The amount of tokens to be claimed and transferred
	 **/
	function _claim(IERC20 token_, address dst_, uint256 amount_) private {
		token_.safeTransferFrom(msg.sender, dst_, amount_);
	}
}
