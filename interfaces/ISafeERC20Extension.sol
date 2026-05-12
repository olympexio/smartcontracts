// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ISafeERC20Extension {
	function safeApprove(IERC20 token, address spender, uint256 amount) external;

	function safeTransfer(IERC20 token, address payable target, uint256 amount) external;
}
