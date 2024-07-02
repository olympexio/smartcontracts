// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { AccessControlUpgradeable } from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import { IOlympexOrderLimit } from './interfaces/IOlympexOrderLimit.sol';
import { IOlympexMessenger } from './interfaces/IOlympexMessenger.sol';
import { IOlympexCommon } from './interfaces/IOlympexCommon.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IERC2612 } from '@openzeppelin/contracts/interfaces/IERC2612.sol';

import { OlympexAggregator } from './OlympexAggregator.sol';
import { UniswapV2Aggregator } from './UniswapV2Aggregator.sol';

import './libraries/UniversalERC20.sol';

contract OlympexLimitOrder is
	Initializable,
	PausableUpgradeable,
	AccessControlUpgradeable,
	OwnableUpgradeable,
	IOlympexOrderLimit,
	// IERC2612,
	UUPSUpgradeable
{
	using UniversalERC20 for IERC20;
	/********
	 * INDEX *
	 *********/
	// 1. Type declarations.
	// 2. Constants and state variables.
	// 3. Events.
	// 4. Errors.
	// 5. Modifiers.
	// 6. Functions.
	// 		Order of functions
	// 		6.1 constructor
	// 		6.2 receive function (if exists)
	// 		6.3 fallback function (if exists)
	// 		6.4 external
	// 		6.5 public
	// 		6.6 internal
	// 		6.7 private

	/************************
	 * 1. TYPE DECLARATIONS *
	 ************************/
	// empty

	/******************************
	 * 2. CONSTANTS AND VARIABLES *
	 ******************************/
	bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
	bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
	bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');

	OlympexAggregator private _aggregatorContract;

	/*************
	 * 3. EVENTS *
	 *************/
	// empty

	/*************
	 * 4. ERRORS *
	 *************/
	// empty

	/****************
	 * 5. MODIFIERS *
	 ****************/
	// empty

	/****************
	 * 6. FUNCTIONS *
	 ****************/
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(
		address defaultAdmin,
		address pauser,
		address upgrader,
		OlympexAggregator aggregatorAddress
	) public initializer {
		__Pausable_init();
		__AccessControl_init();
		__Ownable_init(msg.sender);
		__UUPSUpgradeable_init();

		_grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
		_grantRole(PAUSER_ROLE, pauser);
		_grantRole(UPGRADER_ROLE, upgrader);

		_aggregatorContract = aggregatorAddress;
	}

	function pause() public onlyRole(PAUSER_ROLE) {
		_pause();
	}

	function unpause() public onlyRole(PAUSER_ROLE) {
		_unpause();
	}

	/**
	 * @dev Executes a token swap operation, allowing users to exchange tokens on Olympex
	 * @param hermes IOlympexMessenger contract facilitating off-chain communication
	 * @param desc SwapDescription struct containing swap details and parameters
	 * @param messengers Array of MessageDescriptions for interacting with external protocols
	 * @return returnAmount The amount of destination tokens received after the swap
	 **/
	function swap(
		IOlympexMessenger hermes,
		IOlympexCommon.SwapDescription calldata desc,
		IOlympexMessenger.MessageDescription[] calldata messengers
	) external payable whenNotPaused onlyRole(ADMIN_ROLE) returns (uint256 returnAmount) {
		IERC20 srcToken = IERC20(desc.srcToken);

		require(
			!srcToken.isETH(),
			'Not possible make a limit order for eth, you must be weth'
		);

		require(
			IERC20(desc.srcToken).allowance(desc.dstReceiver, address(this)) >= desc.amount,
			'The allowance must be greater or equals than amount'
		);

		require(
			srcToken.universalBalanceOf(desc.dstReceiver) >= desc.amount,
			'The balance of srcToken must be greater or equals than amount'
		);

		IERC20(desc.srcToken).transferFrom(desc.dstReceiver, address(this), desc.amount);

		require(
			srcToken.universalBalanceOf(address(this)) >= desc.amount,
			'The balance of srcToken must be greater or equals than amount in OrderLimit Contract'
		);

		IERC20(desc.srcToken).approve(address(_aggregatorContract), desc.amount);

		returnAmount = _aggregatorContract.swap(hermes, desc, messengers);

		emit LimitOrderEmited(
			SwapType.swap,
			desc.dstReceiver,
			returnAmount,
			address(desc.srcToken),
			address(desc.dstToken)
		);
	}

	/**
	 * @dev Executes a token swap operation using callUniswapTo, allowing users to exchange tokens on Olympex
	 * @param srcToken Origin tokens
	 * @param amount Amount using for make swap
	 * @param minReturn Minimun of token returns
	 * @param pools Poll list using in the swap
	 * @param recipient Address that receive the tokens in the swap
	 * @param firm Parameter for signature and trading volumen
	 * @return returnAmount The amount of destination tokens received after the swap
	 **/
	function callUniswapTo(
		IERC20 srcToken,
		uint256 amount,
		uint256 minReturn,
		bytes32[] calldata pools,
		address payable recipient,
		UniswapV2Aggregator.SignatureData calldata firm
	) external payable returns (uint256 returnAmount) {
		IERC20 srcToken_ = IERC20(srcToken);

		require(
			!srcToken_.isETH(),
			'Not possible make a limit order for eth, you must be weth'
		);

		require(
			IERC20(srcToken_).allowance(recipient, address(this)) >= amount,
			'The allowance must be greater or equals than amount'
		);

		require(
			srcToken.universalBalanceOf(recipient) >= amount,
			'The balance of srcToken must be greater or equals than amount'
		);

		require(
			srcToken.universalBalanceOf(address(this)) >= amount,
			'The balance of srcToken must be greater or equals than amount in OrderLimit Contract'
		);

		IERC20(srcToken).approve(address(_aggregatorContract), amount);

		returnAmount = _aggregatorContract.callUniswapTo(
			srcToken,
			amount,
			minReturn,
			pools,
			recipient,
			firm
		);

		emit LimitOrderEmited(
			SwapType.callUniswapTo,
			recipient,
			returnAmount,
			address(srcToken),
			address(this)
		);
	}

	function setOlympexAggregatorContract(
		OlympexAggregator aggregatorContract
	) external onlyOwner {
		_aggregatorContract = aggregatorContract;
	}

	function getOlympexAggregatorContract()
		external
		view
		onlyRole(ADMIN_ROLE)
		returns (OlympexAggregator)
	{
		return _aggregatorContract;
	}

	receive() external payable {}

	fallback() external payable {}

	function permit(
		address owner,
		address spender,
		uint256 value,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external {}

	function nonces(address owner) external {}

	function getVersion() external pure returns (uint256) {
		return 1;
	}

	function _authorizeUpgrade(
		address newImplementation
	) internal override onlyRole(UPGRADER_ROLE) {}
}
