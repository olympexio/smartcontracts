// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IOlympexRouter } from './IOlympexRouter.sol';

interface ICrossAggregator {
	error externalCallFailed(string);

	function crossSwap(
		address router_,
		IOlympexRouter.SwapParams calldata params_
	) external payable returns (IOlympexRouter.SwapResult memory);
}
