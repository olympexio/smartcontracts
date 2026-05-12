// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract PercentageManager {
	error InvalidPercentage();

	/// @dev Denominator for percentage calculation. This value represents 100%
	uint256 public constant PERCENTAGE_DENOMINATOR = 1_000_000;

	/// @dev Modifier to ensure that the provided percentage is valid.
	// Thrown if percentage is outside valid range
	modifier validPercentage(uint256 perc_) {
		if (perc_ < 0 || perc_ > PERCENTAGE_DENOMINATOR) revert InvalidPercentage();
		_;
	}
}
