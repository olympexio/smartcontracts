// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

import { IUniswapV3MulticallQuoter } from '../interfaces/IUniswapV3MulticallQuoter.sol';

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
contract UniswapV3MulticallQuoter is IUniswapV3MulticallQuoter {
	/// @inheritdoc IUniswapV3MulticallQuoter
	function multicall(
		address to,
		bytes[] calldata data
	) public payable returns (bytes[] memory results) {
		results = new bytes[](data.length);

		for (uint256 i = 0; i < data.length; i++) {
			(bool success, bytes memory result) = to.call(data[i]);

			if (!success) {
				// Next 5 lines from https://ethereum.stackexchange.com/a/83577
				if (result.length < 68) revert();
				assembly {
					result := add(result, 0x04)
				}
				revert(abi.decode(result, (string)));
			}

			results[i] = result;
		}
	}
}
