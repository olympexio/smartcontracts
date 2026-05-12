// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IOlympexRouter } from './IOlympexRouter.sol';

interface IAggregator {
	error externalCallFailed(string);

	/**
	 * @dev Executes a token swap operation, allowing users to exchange tokens on Olympex
	 **/
	function swap(
		address router_,
		IOlympexRouter.SwapParams calldata params_
	) external payable returns (IOlympexRouter.SwapResult memory);
}
