// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

contract totalEclipseNFT is ERC721, Ownable, ERC2981 {
    uint256 private _nextTokenId = 1; // Start tokenId indexing at 1

    /**
     * @param _royaltyFeesInBips The royalty fee percentage in basis points (1% = 100 bips).
     * @param _royaltyReceiverAddress The address that will receive royalty payments.
     * @param _approvalToVaultAddress The address approved to operate all NFTs (e.g., for fractionalization).
     */

    constructor(
        uint96 _royaltyFeesInBips,
        address _royaltyReceiverAddress,
        address _approvalToVaultAddress
    ) ERC721("Total Eclipse", "TEA") Ownable(msg.sender) {
        setRoyaltyInfo(_royaltyReceiverAddress, _royaltyFeesInBips); // Royalty informations
        collectiveMinting(_royaltyReceiverAddress, 10); // Minting the collection at once
        _setApprovalForAll(
            _royaltyReceiverAddress,
            _approvalToVaultAddress,
            true
        ); // Approval function call to operate the collection for fractionalization
    }

    // This function is used to set the metadata for the NFTs
    function _baseURI() internal pure override returns (string memory) {
        return
            "https://ipfs.filebase.io/ipfs/QmXcA1rEeoUvcMnLQeFJv3LvUEeXijfBkqJgE5LCGa9MAP/"; //Have to change for every albums
    }

    // Mint function to create multiple NFTs at once in an album
    function collectiveMinting(address _to, uint256 _mintAmount)
        private
        onlyOwner
    {
        for (uint256 i = 0; i < _mintAmount; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(_to, tokenId);
        }
    }

    // To check the NFT count
    function totalSupply() public view returns (uint256) {
        return _nextTokenId - 1; // Because the first token is indexed at 1
    }

    // Set Royalty for all the NFTs of this contract
    function setRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips)
        public
        onlyOwner
    {
        _setDefaultRoyalty(_receiver, _royaltyFeesInBips);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}