// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import './DigitalSignatureWhitelist.sol';

import 'hardhat/console.sol';

contract OlympexPas is Ownable, ERC721, DigitalSignatureWhitelist {
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
	uint256 public constant MAX_WL_TOKENS = 10;

	/// @dev Maximum number of NFTs that can be minted
	uint256 public constant MAX_SUPPLY = 20000;

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

	/****************
	 * 5. MODIFIERS *
	 ****************/
	// empty

	/****************
	 * 5. FUNCTIONS *
	 ****************/
	constructor(
		string memory name_,
		string memory symbol_,
		address signerAddress_,
		string memory nftURI_
	) ERC721(name_, symbol_) Ownable(msg.sender) DigitalSignatureWhitelist(signerAddress_) {
		_nftURI = nftURI_;
	}

	function currentCount() external view returns (uint256) {
		return _tokenIdCounter;
	}

	function mint(bytes memory signature) external {
		require(verifyAddressSigner(signature), 'SIGNATURE_VALIDATION_FAILED');

		uint256 _tokenId = ++_tokenIdCounter;

		require(_tokenId <= MAX_SUPPLY, 'Fulfilled supply');

		// TODO: en que parte de los requerimientos se definió esta validación? esto fue colocado
		// por Joaquín, habría que corroborar si realmente es un requerimiento
		require(MAX_WL_TOKENS >= balanceOf(msg.sender), 'Claim limit exceeded.');

		_safeMint(msg.sender, _tokenId);

		emit Minted(msg.sender, _tokenId);
	}

	function setBaseURI(string memory nftURI_) external onlyOwner {
		_nftURI = nftURI_;
	}

	function tokenURI(
		uint256 tokenId_
	) public view virtual override returns (string memory) {
		_requireOwned(tokenId_);
		return string(abi.encodePacked(_nftURI, '/', tokenId_.toString(), '.json'));
	}
}
