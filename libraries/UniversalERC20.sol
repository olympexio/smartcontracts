// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

library UniversalERC20 {
	using SafeERC20 for IERC20;

	IERC20 internal constant ZERO_ADDRESS =
		IERC20(0x0000000000000000000000000000000000000000);
	IERC20 internal constant ETH_ADDRESS =
		IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
	IERC20 internal constant MATIC_ADDRESS =
		IERC20(0x0000000000000000000000000000000000001010);

	function universalTransfer(IERC20 token, address payable to, uint256 amount) internal {
		if (amount > 0) {
			if (isETH(token)) {
				(bool sent, ) = to.call{ value: amount }('');
				require(sent, 'Failed to send ETH');
			} else {
				token.safeTransfer(to, amount);
			}
		}
	}

	/**
	 * @dev Handles token transfers from a specific address.
	 * @param token Token to transfer (ETH or ERC20)
	 * @param from Address that sends the tokens
	 * @param to Address that receives the tokens
	 * @param amount Amount to transfer
	 **/
	function universalTransferFrom(
		IERC20 token,
		address from,
		address to,
		uint256 amount
	) internal {
		if (isETH(token)) {
			(bool sent, ) = to.call{ value: amount }('');
			require(sent, 'Failed to send ETH');
		} else {
			token.safeTransferFrom(from, to, amount);
		}
	}

	function universalApprove(IERC20 token, address to, uint256 amount) internal {
		require(!isETH(token), 'Approve called on ETH');

		if (amount == 0) {
			token.safeIncreaseAllowance(to, 0);
		} else {
			uint256 allowance = token.allowance(address(this), to);
			if (allowance < amount) {
				if (allowance > 0) {
					token.safeIncreaseAllowance(to, 0);
				}
				token.safeIncreaseAllowance(to, amount);
			}
		}
	}

	function universalBalanceOf(
		IERC20 token,
		address account
	) internal view returns (uint256) {
		if (isETH(token)) {
			return account.balance;
		} else {
			return token.balanceOf(account);
		}
	}

	function isETH(IERC20 token) internal pure returns (bool) {
		return
			address(token) == address(ETH_ADDRESS) ||
			address(token) == address(MATIC_ADDRESS) ||
			address(token) == address(ZERO_ADDRESS);
	}
}
