// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { AccessControl } from '@openzeppelin/contracts/access/AccessControl.sol';

import { IOlympex } from './interfaces/IOlympex.sol';
import { IAggregator } from './interfaces/IAggregator.sol';
import { ICrossAggregator } from './interfaces/ICrossAggregator.sol';
import { IOlympexRouter } from './interfaces/IOlympexRouter.sol';

contract OlympexRouter is IOlympexRouter, AccessControl {
	bytes32 public constant OWNER_ROLE = keccak256('OWNER_ROLE');
	bytes32 public constant PROTOCOL_ROLE = keccak256('PROTOCOL_ROLE');

	address public owner;

	mapping(string => IOlympexRouter.Aggregator) private aggregators;

	constructor(address protocol) {
		_grantRole(DEFAULT_ADMIN_ROLE, protocol);
		_grantRole(PROTOCOL_ROLE, protocol);
	}

	function setOwner(address owner_) external onlyRole(PROTOCOL_ROLE) {
		if (owner != address(0)) {
			_revokeRole(OWNER_ROLE, owner);
		}
		_grantRole(OWNER_ROLE, owner_);
		owner = owner_;
	}

	function addAggregator(
		address router_,
		address middleware_,
		string calldata dexName_
	) external onlyRole(PROTOCOL_ROLE) {
		if (middleware_ == address(0) || router_ == address(0)) revert InvalidAggregator();
		if (aggregators[dexName_].middleware != address(0)) revert AggregatorAlreadyExists();

		aggregators[dexName_] = IOlympexRouter.Aggregator({
			router: router_,
			middleware: middleware_
		});
	}

	function removeAggregator(
		string calldata dexName_
	) external onlyRole(PROTOCOL_ROLE) returns (address) {
		address middleware = aggregators[dexName_].middleware;

		if (middleware == address(0)) revert InvalidAggregator();

		delete aggregators[dexName_];

		return middleware;
	}

	/**
	 * @inheritdoc IOlympexRouter
	 */
	function swap(
		string calldata dexName_,
		SwapParams calldata params_
	) external payable onlyRole(OWNER_ROLE) returns (SwapResult memory) {
		IOlympexRouter.Aggregator memory aggregator = getAggregator(dexName_);

		IOlympexRouter.SwapResult memory result = IAggregator(aggregator.middleware).swap{
			value: msg.value
		}(aggregator.router, params_);

		return result;
	}

	function crossSwap(
		string calldata dexName_,
		SwapParams calldata params_
	) external payable onlyRole(OWNER_ROLE) returns (SwapResult memory) {
		IOlympexRouter.Aggregator memory aggregator = getAggregator(dexName_);

		IOlympexRouter.SwapResult memory result = ICrossAggregator(aggregator.middleware)
			.crossSwap{ value: msg.value }(aggregator.router, params_);

		return result;
	}

	function getAggregator(
		string calldata dexName_
	) public view returns (IOlympexRouter.Aggregator memory) {
		if (aggregators[dexName_].middleware == address(0)) revert InvalidAggregator();
		return aggregators[dexName_];
	}
}
