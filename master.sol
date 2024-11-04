// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
contract NoirSoulSyndicateMaster is ERC1155, Ownable, ERC1155Supply, ERC1155Burnable,
ERC1155Pausable, ERC2981, ReentrancyGuard {
// Metadata for each digital asset, referenced by item IDs
struct AssetMetadata {
string name;
string uri;
uint256 royaltyBips;
}
// Mapping from item ID to asset metadata
mapping(uint256 => AssetMetadata) public assets;
// Events
event AssetCreated(uint256 indexed assetId, string name, string uri, uint256 royaltyBips,
uint256 totalSupply);
event AssetMinted(uint256 indexed assetId, address indexed to, uint256 amount);
event AssetAuctioned(uint256 indexed assetId, address indexed seller, uint256 minBid);
event AuctionClosed(uint256 indexed assetId, address indexed winner, uint256 bidAmount);
// Item ID tracking
uint256 private _nextAssetId = 1;
// Constructor: initialize with base URI
constructor(string memory baseURI) ERC1155(baseURI) {}
// Function to create a new digital asset
function createAsset(
string memory name,
string memory uri,
uint256 totalSupply,
uint96 royaltyBips
) external onlyOwner returns (uint256) {
uint256 assetId = _nextAssetId++;
assets[assetId] = AssetMetadata(name, uri, royaltyBips);
// Set default royalty for the asset
_setTokenRoyalty(assetId, msg.sender, royaltyBips);
// Mint the initial supply to the owner
_mint(msg.sender, assetId, totalSupply, "");
emit AssetCreated(assetId, name, uri, royaltyBips, totalSupply);
return assetId;
}
// Mint function for additional supply of an existing asset
function mintAsset(uint256 assetId, address to, uint256 amount) external onlyOwner {
require(bytes(assets[assetId].name).length != 0, "Asset does not exist");
_mint(to, assetId, amount, "");
emit AssetMinted(assetId, to, amount);
}
// Override for ERC1155's URI function to return each asset's URI
function uri(uint256 assetId) public view override returns (string memory) {
return assets[assetId].uri;
}
// Pause/Unpause contract
function pause() external onlyOwner {
_pause();
}
function unpause() external onlyOwner {
_unpause();
}
// Auction functions: Begin, Bid, and End
struct Auction {
address payable seller;
uint256 minBid;
uint256 highestBid;
address payable highestBidder;
bool active;
}
mapping(uint256 => Auction) public auctions;
function startAuction(uint256 assetId, uint256 minBid) external nonReentrant onlyOwner {
require(!auctions[assetId].active, "Auction already active for asset");
auctions[assetId] = Auction({
seller: payable(msg.sender),
minBid: minBid,
highestBid: 0,
highestBidder: payable(address(0)),
active: true
});
emit AssetAuctioned(assetId, msg.sender, minBid);
}
function bid(uint256 assetId) external payable nonReentrant {
Auction storage auction = auctions[assetId];
require(auction.active, "Auction is not active");
require(msg.value > auction.minBid && msg.value > auction.highestBid, "Bid not high
enough");
// Refund the previous highest bidder
if (auction.highestBid > 0) {
auction.highestBidder.transfer(auction.highestBid);
}
auction.highestBid = msg.value;
auction.highestBidder = payable(msg.sender);
}
function endAuction(uint256 assetId) external nonReentrant {
Auction storage auction = auctions[assetId];
require(auction.active, "Auction is not active");
auction.active = false;
// Transfer asset to the highest bidder if there was a bid
if (auction.highestBid > 0) {
_safeTransferFrom(auction.seller, auction.highestBidder, assetId, 1, "");
auction.seller.transfer(auction.highestBid);
emit AuctionClosed(assetId, auction.highestBidder, auction.highestBid);
} else {
// No bids were made
emit AuctionClosed(assetId, address(0), 0);
}
}
// Royalty function to set custom royalty for each token
function setAssetRoyalty(uint256 assetId, address receiver, uint96 royaltyBips) external
onlyOwner {
_setTokenRoyalty(assetId, receiver, royaltyBips);
}
// Override supportsInterface for ERC2981
function supportsInterface(bytes4 interfaceId)
public
view
override(ERC1155, ERC2981)
returns (bool)
{
return super.supportsInterface(interfaceId);
}
// Internal Hooks
function _beforeTokenTransfer(
address operator,
address from,
address to,
uint256[] memory ids,
uint256[] memory amounts,
bytes memory data
) internal override(ERC1155, ERC1155Pausable) {
super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
}
}