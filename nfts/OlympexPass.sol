// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { ERC721 } from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { DigitalSignatureWhitelist, ECDSA } from './DigitalSignatureWhitelist.sol';

contract OlympexPass is ERC721, DigitalSignatureWhitelist {
	using ECDSA for bytes32;
	using Strings for uint256;

	/*********
	 * INDEX *
	 *********/
	// 1. Type declarations.
	// 2. Constants and variables.
	// 3. mappings.
	// 4. Events.
	// 5. modifiers.
	// 6. Functions.

	/************************
	 * 1. TYPE DECLARATIONS *
	 ************************/
	// empty

	/******************************
	 * 2. CONSTANTS AND VARIABLES *
	 ******************************/
	/// @dev Maximum number of NFTs that can be minted
	uint256 public MAX_SUPPLY = 10_000;

	/// @dev Variable used for indicate if the variable can be to modify
	bool public freezeVariable = false;

	/// @dev Counter of minted NFT identifiers
	uint256 private _tokenIdCounter;

	/// @dev Base URL for NFT metadata
	string private _nftURI;

	/***************
	 * 3. MAPPINGS *
	 ***************/
	// empty

	/*************
	 * 4. Events *
	 *************/
	event Minted(address indexed user_, uint256 tokenId_);

	event SetBaseURI(string indexed nftURI_);

	event SetMaxSupply(uint256 maxSupply);

	event FrozenVariables();

	/****************
	 * 5. MODIFIERS *
	 ****************/
	modifier freezable() {
		require(!freezeVariable, 'The Variables of contract has been frozen.');
		_;
	}

	/****************
	 * 5. FUNCTIONS *
	 ****************/
	/**
	 * @param name_ Name of the NFT collection
	 * @param symbol_ Symbol of the NFT collection
	 * @param signerAddress_ Wallet address authorized to sign backend transactions
	 * @param nftURI_ Uri path for nfts
	 **/
	constructor(
		string memory name_,
		string memory symbol_,
		address signerAddress_,
		string memory nftURI_
	) DigitalSignatureWhitelist(signerAddress_) ERC721(name_, symbol_) {
		_nftURI = nftURI_;
	}

	function currentCount() external view returns (uint256) {
		return _tokenIdCounter;
	}

	function mint(bytes memory signature) external {
		require(verifyAddressSigner(signature), 'SIGNATURE_VALIDATION_FAILED');

		uint256 _tokenId = ++_tokenIdCounter;

		require(_tokenId <= MAX_SUPPLY, 'Fulfilled supply');

		_safeMint(msg.sender, _tokenId);

		emit Minted(msg.sender, _tokenId);
	}

	function setBaseURI(string memory nftURI_) external onlyOwner {
		_nftURI = nftURI_;

		emit SetBaseURI(nftURI_);
	}

	function setMaxSupply(uint256 maxSupply) external onlyOwner freezable {
		MAX_SUPPLY = maxSupply;
		emit SetMaxSupply(maxSupply);
	}

	function frozenVariables() external onlyOwner freezable {
		freezeVariable = true;
		emit FrozenVariables();
	}

	function tokenURI(
		uint256 tokenId_
	) public view virtual override returns (string memory) {
		_requireOwned(tokenId_);
		return string(abi.encodePacked(_nftURI, '/', tokenId_.toString(), '.json'));
	}
}
