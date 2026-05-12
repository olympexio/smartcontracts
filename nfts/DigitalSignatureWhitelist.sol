// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

import { ECDSA } from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import { MessageHashUtils } from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

abstract contract DigitalSignatureWhitelist is Ownable {
	address public _signerAddress;

	constructor(address signerAddress_) Ownable(msg.sender) {
		_signerAddress = signerAddress_;
	}

	function changeSignerAddress(address _newSigner) public onlyOwner {
		_signerAddress = _newSigner;
	}

	function verifyAddressSigner(bytes memory signature) public view returns (bool) {
		bytes32 messageHash = keccak256(abi.encodePacked(msg.sender));
		return
			_signerAddress ==
			ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature);
	}
}
