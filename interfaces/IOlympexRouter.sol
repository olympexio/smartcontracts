// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IOlympex } from './IOlympex.sol';
import { IFeeDistributor } from './IFeeDistributor.sol';

interface IOlympexRouter {
	/**
	 * @dev Error thrown when an invalid aggregator is specified.
	 *
	 * @notice This error indicates that the provided aggregator name or address
	 * does not correspond to a registered aggregator in the contract.
	 */
	error InvalidAggregator();

	/**
	 * @dev Error thrown when an attempt is made to register an aggregator that already exists.
	 *
	 * @notice This error indicates that the aggregator name or address provided
	 * is already associated with a registered aggregator in the contract.
	 */
	error AggregatorAlreadyExists();

	/**
	 * @title Aggregator
	 * @dev Represents the configuration of a DEX aggregator, including its router and middleware addresses.
	 *
	 * @notice This struct is used to store and manage information about different DEX aggregators
	 * that can be used for token swaps.
	 */
	struct Aggregator {
		/**
		 * @dev The address of the router contract for the DEX aggregator.
		 * This contract is responsible for executing the swap operations.
		 */
		address router;
		/**
		 * @dev The address of the middleware contract for the DEX aggregator.
		 * This contract may perform additional operations or validations before or after the swap.
		 */
		address middleware;
	}

	/**
	 * @title SwapParams
	 * @dev Represents the parameters required for a token swap operation.
	 *
	 * @notice This struct encapsulates all the necessary information to execute a swap,
	 * including data for the DEX aggregator, swap description, and fee distribution.
	 */
	struct SwapParams {
		/**
		 * @dev The data payload to be sent to the DEX aggregator's router.
		 * This data contains the encoded function call and parameters for the swap.
		 */
		bytes data;
		/**
		 * @dev Additional information required by each aggregator or middleware.
		 * This parameter is used to pass extra data that may be needed, which
		 * will later be decoded within each middleware as necessary.
		 **/
		bytes extraData;
		/**
		 * @dev The description of the swap, including token addresses, amounts, and other relevant information.
		 */
		IOlympex.SwapDescription description;
		/**
		 * @dev The description of the fees to be distributed, including the discount rate and other fee-related details.
		 */
		IFeeDistributor.FeeDescription feeDescription;
	}

	/**
	 * @title SwapResult
	 * @dev Represents the result of a swap operation, including information about fees and payment tokens.
	 *
	 * @notice This struct is used to encapsulate the outcome of a swap, allowing the contract
	 * to determine how fees should be distributed and which payment token was used.
	 */
	struct SwapResult {
		/**
		 * @dev The ERC-20 token used for payment in the swap.
		 * This field indicates the token that was transferred or received as part of the swap.
		 */
		IERC20 paymentToken;
		/**
		 * @dev A boolean indicating whether fees should be distributed from the swap result.
		 * If set to `true`, fees will be calculated and distributed according to the contract's logic.
		 * If set to `false`, no fees will be distributed.
		 */
		bool distributeFees;
		/**
		 * @dev A boolean indicating whether fees should be distributed by percentage or by a fixed amount.
		 * If set to `true`, fees will be calculated as a percentage of the swap amount.
		 * If set to `false`, fees will be a fixed amount.
		 */
		bool feesByPercentage;
	}

	/**
	 * @dev Executes a synchronous token swap operation on Olympex.
	 * This function allows users to exchange tokens using a specified DEX aggregator.
	 *
	 * @param dexName_ The name of the DEX aggregator to be used for the swap (e.g., Uniswap, SushiSwap).
	 * @param params_ A struct containing the necessary parameters for the swap operation.
	 *
	 * @notice The swap is performed synchronously, meaning the transaction will revert if the swap fails.
	 *
	 * @return A boolean indicating whether the swap operation was successfully executed.
	 *
	 * @custom:security Requires valid signature from the signer address (_signerAddress) to authorize the swap.
	 * @custom:security Ensure that the sender has approved the contract to spend the source tokens.
	 */
	function swap(
		string calldata dexName_,
		SwapParams calldata params_
	) external payable returns (SwapResult memory);

	function crossSwap(
		string calldata dexName_,
		SwapParams calldata params_
	) external payable returns (SwapResult memory);
}
