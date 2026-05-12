// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC2612 } from '@openzeppelin/contracts/interfaces/IERC2612.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import { AccessControlUpgradeable } from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { ECDSA } from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import { MessageHashUtils } from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

import { IOlympexAsyncOrderV3 as IOlympexAsyncOrder } from './interfaces/IOlympexAsyncOrder.sol';

import { UniversalERC20 } from './libraries/UniversalERC20.sol';
import { RevertReasonParser } from './libraries/RevertReasonParser.sol';

contract OlympexAsyncOrderV3 is
	Initializable,
	PausableUpgradeable,
	AccessControlUpgradeable,
	IOlympexAsyncOrder,
	IERC2612,
	UUPSUpgradeable
{
	using UniversalERC20 for IERC20;
	using ECDSA for bytes32;
	using MessageHashUtils for bytes32;

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
	bytes32 public constant LIMIT_ORDER_ROLE = keccak256('LIMIT_ORDER_ROLE');
	bytes32 public constant DCA_ROLE = keccak256('DCA_ROLE');

	/// @dev storage gaps for contract upgrade
	uint256[50] __gap;

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
		address limit_order_role,
		address dca_role
	) public initializer {
		__UUPSUpgradeable_init();
		__AccessControl_init();
		__Pausable_init();

		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_grantRole(ADMIN_ROLE, defaultAdmin);
		_grantRole(PAUSER_ROLE, pauser);
		_grantRole(UPGRADER_ROLE, upgrader);
		_grantRole(LIMIT_ORDER_ROLE, limit_order_role);
		_grantRole(DCA_ROLE, dca_role);
	}

	function pause() external onlyRole(PAUSER_ROLE) {
		_pause();
	}

	function unpause() external onlyRole(PAUSER_ROLE) {
		_unpause();
	}

	/**
	 * @inheritdoc IOlympexAsyncOrder
	 */
	function DCASwap(
		address aggregatorContract,
		address middlewareAddress,
		OrderDescription calldata orderData
	) external payable whenNotPaused onlyRole(DCA_ROLE) returns (uint256) {
		uint256 gasStart = gasleft();

		uint256 balanceBefore = orderData.dstToken.universalBalanceOf(address(this));

		_verifySignatureDCAOrder(orderData);

		(bool success, bytes memory returnData, uint256 returnAmount) = _execute(
			aggregatorContract,
			middlewareAddress,
			orderData
		);

		if (!success) {
			revert(
				RevertReasonParser.parse(returnData, 'Olympex limit order external call failed: ')
			);
		}

		if (
			!(orderData.dstToken.universalBalanceOf(address(this)) - balanceBefore ==
				returnAmount)
		) {
			revert('Balance is different of return amount');
		}

		(uint256 costInERC20, uint256 costInNativeWei, uint256 gasUsed) = _getCostTransaction(
			gasStart,
			orderData.feeConvertionRate,
			address(orderData.dstToken)
		);

		orderData.dstToken.universalTransfer(payable(msg.sender), costInERC20);

		orderData.dstToken.universalTransfer(
			payable(orderData.maker),
			returnAmount - costInERC20
		);

		emit DCAOrderEmited(
			orderData.taker,
			returnAmount,
			address(orderData.srcToken),
			address(orderData.dstToken),
			gasUsed,
			costInNativeWei,
			costInERC20,
			orderData.feeConvertionRate,
			tx.gasprice
		);

		return returnAmount;
	}

	/**
	 * @inheritdoc IOlympexAsyncOrder
	 */
	function limitOrderSwap(
		address aggregatorContract,
		address middlewareAddress,
		OrderDescription calldata limitOrderData
	) external payable whenNotPaused onlyRole(LIMIT_ORDER_ROLE) returns (uint256) {
		uint256 gasStart = gasleft();

		uint256 balanceBefore = limitOrderData.dstToken.universalBalanceOf(address(this));

		_verifySignatureLimitOrder(limitOrderData);

		(bool success, bytes memory returnData, uint256 returnAmount) = _execute(
			aggregatorContract,
			middlewareAddress,
			limitOrderData
		);

		if (!success) {
			revert(
				RevertReasonParser.parse(returnData, 'Olympex limit order external call failed: ')
			);
		}

		if (
			!(limitOrderData.dstToken.universalBalanceOf(address(this)) - balanceBefore ==
				returnAmount)
		) {
			revert('Balance is different of return amount');
		}

		(uint256 costInERC20, uint256 costInNativeWei, uint256 gasUsed) = _getCostTransaction(
			gasStart,
			limitOrderData.feeConvertionRate,
			address(limitOrderData.srcToken)
		);

		if (
			limitOrderData.srcToken.allowance(limitOrderData.maker, address(this)) < costInERC20
		) {
			revert('The allowance must be greater or equals than fee');
		}

		limitOrderData.srcToken.universalTransferFrom(
			limitOrderData.maker,
			msg.sender,
			costInERC20
		);

		limitOrderData.dstToken.universalTransfer(
			payable(limitOrderData.maker),
			returnAmount
		);

		emit LimitOrderEmited(
			limitOrderData.maker,
			limitOrderData.taker,
			returnAmount,
			address(limitOrderData.srcToken),
			address(limitOrderData.dstToken),
			gasUsed,
			costInNativeWei,
			costInERC20,
			limitOrderData.feeConvertionRate,
			tx.gasprice
		);

		return returnAmount;
	}

	/**
	 * @inheritdoc IOlympexAsyncOrder
	 */
	function limitOrderSwapBulk(
		address aggregatorContract,
		address middlewareAddress,
		OrderDescription[] calldata limitOrderData
	) external payable whenNotPaused onlyRole(ADMIN_ROLE) {
		for (uint256 i = 0; i < limitOrderData.length; i++) {
			uint256 gasStart = gasleft();

			uint256 balanceBefore = limitOrderData[i].dstToken.universalBalanceOf(
				address(this)
			);

			_verifySignatureLimitOrder(limitOrderData[i]);

			(bool success, bytes memory returnData, uint256 returnAmount) = _execute(
				aggregatorContract,
				middlewareAddress,
				limitOrderData[i]
			);

			if (
				!(limitOrderData[i].dstToken.universalBalanceOf(address(this)) - balanceBefore ==
					returnAmount)
			) {
				revert('Balance is different of return amount');
			}

			(
				uint256 costInERC20,
				uint256 costInNativeWei,
				uint256 gasUsed
			) = _getCostTransaction(
					gasStart,
					limitOrderData[i].feeConvertionRate,
					address(limitOrderData[i].srcToken)
				);

			if (
				limitOrderData[i].srcToken.allowance(limitOrderData[i].maker, address(this)) <
				costInERC20
			) {
				revert('The allowance must be greater or equals than fee');
			}

			limitOrderData[i].srcToken.universalTransferFrom(
				limitOrderData[i].maker,
				msg.sender,
				costInERC20
			);

			limitOrderData[i].dstToken.universalTransfer(
				payable(limitOrderData[i].maker),
				returnAmount
			);

			if (success) {
				emit LimitOrderEmited(
					limitOrderData[i].maker,
					limitOrderData[i].taker,
					returnAmount,
					address(limitOrderData[i].srcToken),
					address(limitOrderData[i].dstToken),
					gasUsed,
					costInNativeWei,
					costInERC20,
					limitOrderData[i].feeConvertionRate,
					tx.gasprice
				);
			} else {
				emit LimitOrderError(
					limitOrderData[i].taker,
					returnAmount,
					address(limitOrderData[i].srcToken),
					address(limitOrderData[i].dstToken),
					RevertReasonParser.parse(
						returnData,
						'Olympex limit order external call failed: '
					)
				);
			}
		}
	}

	/**
	 * @notice Executes a order by interacting with an aggregator contract
	 * @dev This function handles token transfers, allowances, and calls to the aggregator contract
	 * @param aggregatorContract The address of the aggregator contract that will execute the order
	 * @param middlewareAddress The address of middleware that make the swap used for the aggregator
	 * @param orderData A struct containing all the details of the order, including tokens, amounts, and calldata
	 * @return success A boolean indicating whether the call to the aggregator contract was successful
	 * @return returnData The raw data returned from the aggregator contract call
	 * @return returnAmount The amount of the destination token returned by the swap, decoded from returnData
	 */
	function _execute(
		address aggregatorContract,
		address middlewareAddress,
		OrderDescription calldata orderData
	) private returns (bool success, bytes memory returnData, uint256 returnAmount) {
		IERC20 srcToken = IERC20(orderData.srcToken);

		require(!srcToken.isETH(), 'Not possible make a order for eth, you must be weth');

		require(
			IERC20(orderData.srcToken).allowance(orderData.maker, address(this)) >=
				orderData.amount,
			'The allowance must be greater or equals than amount'
		);

		require(
			srcToken.universalBalanceOf(orderData.maker) >= orderData.amount,
			'The balance of srcToken must be greater or equals than amount'
		);

		IERC20(orderData.srcToken).transferFrom(
			orderData.maker,
			address(this),
			orderData.amount
		);

		require(
			srcToken.universalBalanceOf(address(this)) >= orderData.amount,
			'The balance of srcToken must be greater or equals than amount in OrderLimit Contract'
		);

		IERC20(orderData.srcToken).approve(address(middlewareAddress), orderData.amount);

		if (orderData.gasLimit > 0) {
			(success, returnData) = address(aggregatorContract).call{
				value: orderData.value,
				gas: orderData.gasLimit
			}(orderData.data);
		} else {
			(success, returnData) = address(aggregatorContract).call{ value: orderData.value }(
				orderData.data
			);
		}

		returnAmount = abi.decode(returnData, (uint256));
	}

	function _getCostTransaction(
		uint256 gasStart,
		uint256 feeConvertionRate,
		address erc20Address
	) private view returns (uint256 costInERC20, uint256 costInNativeWei, uint256 gasUsed) {
		gasUsed = gasStart - gasleft() + 21000;

		costInNativeWei = (gasUsed * tx.gasprice);

		costInERC20 = (costInNativeWei * feeConvertionRate) / (10 ** 18);

		costInERC20 = ((costInERC20 * 10 ** IERC20Metadata(erc20Address).decimals()) /
			10 ** 18);

		return (costInERC20, costInNativeWei, gasUsed);
	}

	function _transferToken(
		OrderDescription memory limitOrderData,
		uint256 returnAmount,
		uint256 fee
	) private {
		limitOrderData.srcToken.universalTransferFrom(limitOrderData.maker, msg.sender, fee);

		limitOrderData.srcToken.universalTransferFrom(
			limitOrderData.maker,
			msg.sender,
			returnAmount - fee
		);
	}

	function _verifySignatureDCAOrder(OrderDescription memory orderData) private pure {
		if (
			!(keccak256(
				abi.encodePacked(
					orderData.maker,
					orderData.taker,
					orderData.srcToken,
					orderData.dstToken
				)
			).toEthSignedMessageHash().recover(orderData.signature) == orderData.maker)
		) {
			revert('Invalid DCA order signature');
		}
	}

	function _verifySignatureLimitOrder(OrderDescription memory orderData) private pure {
		if (
			!(keccak256(
				abi.encodePacked(
					orderData.maker,
					orderData.taker,
					orderData.srcToken,
					orderData.dstToken
				)
			).toEthSignedMessageHash().recover(orderData.signature) == orderData.maker)
		) {
			revert('Invalid limit order signature');
		}
	}

	function permit(
		address owner,
		address spender,
		uint256 value,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external {}

	function DOMAIN_SEPARATOR() external view returns (bytes32) {}

	function nonces(address owner) external view returns (uint256) {}

	function getVersion() external pure returns (string memory) {
		return 'v3.0.0';
	}

	function _authorizeUpgrade(
		address newImplementation
	) internal override onlyRole(UPGRADER_ROLE) {}
}
