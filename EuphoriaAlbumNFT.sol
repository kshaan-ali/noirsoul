// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
contract EuphoriaAlbumNFT is ERC721, Ownable, ERC2981 {
using Counters for Counters.Counter;
// Track Metadata Structure
struct Track {
string title;
string isrc;
uint256 pricePerShare;
uint256 sharesRemaining;
bool isAvailable;
uint256 totalRoyalty;
mapping(address => uint256) shareOwnership; // Map owner to their share count
}
// Track Mapping by ID
mapping(uint256 => Track) public tracks;
Counters.Counter private _trackCounter;
// Constants
uint256 public constant MAX_SHARES_PER_TRACK = 1250;
uint256 public constant SHARE_PRICE_USD = 1250; // $12.50 USD in cents (convert to$MATIC for actual purchase)
// Events
event TrackCreated(uint256 trackId, string title, string isrc);
event SharePurchased(uint256 trackId, address buyer, uint256 shares);
event RoyaltyAccrued(uint256 trackId, uint256 amount);
event RoyaltyWithdrawn(uint256 trackId, address owner, uint256 amount);
constructor(uint96 _royaltyFeesInBips, address _royaltyReceiverAddress)
ERC721("Euphoria Album", "TEA") Ownable(msg.sender)
{
// Set royalty information
setRoyaltyInfo(_royaltyReceiverAddress, _royaltyFeesInBips);
// Transfer ownership to Noir Soul Syndicate’s wallet address
transferOwnership(0xA39c821C6999acC27D71882b1Ca49fDdfA264cCA);
}
// Base URI for metadata
function _baseURI() internal pure override returns (string memory) {
return
"https://inherent-scarlet-tarsier.myfilebase.com/ipfs/QmPtSf9wkwsTztFG2Lz2trLMMo9pjma15VME9ykpQLndyi/";
}
// Create a new track as an NFT
function createTrack(string memory _title, string memory _isrc) public onlyOwner {
uint256 trackId = _trackCounter.current();
_safeMint(msg.sender, trackId);
Track storage track = tracks[trackId];
track.title = _title;
track.isrc = _isrc;
track.pricePerShare = SHARE_PRICE_USD;
track.sharesRemaining = MAX_SHARES_PER_TRACK;
track.isAvailable = true;
_trackCounter.increment();
emit TrackCreated(trackId, _title, _isrc);
}
// Purchase shares of a track
function purchaseShares(uint256 trackId, uint256 numShares) public payable {
Track storage track = tracks[trackId];
require(track.isAvailable, "Track not available");
require(numShares > 0 && numShares <= track.sharesRemaining, "Invalid number ofshares");
require(msg.value >= numShares * track.pricePerShare * 1e16, "Insufficient payment"); //Convert cents to MATIC
track.shareOwnership[msg.sender] += numShares;
track.sharesRemaining -= numShares;
// Transfer funds to the contract owner
payable(owner()).transfer(msg.value);
emit SharePurchased(trackId, msg.sender, numShares);
}
// Accumulate royalty for a specific track
function accumulateRoyalty(uint256 trackId) public payable onlyOwner {
Track storage track = tracks[trackId];
require(msg.value > 0, "Royalty amount must be greater than zero");
track.totalRoyalty += msg.value;
emit RoyaltyAccrued(trackId, msg.value);
}
// Calculate the share percentage of an owner for a track
function getOwnerSharePercentage(uint256 trackId, address owner) public view returns
(uint256) {
Track storage track = tracks[trackId];
uint256 ownerShares = track.shareOwnership[owner];
return (ownerShares * 1e18) / MAX_SHARES_PER_TRACK; // Return percentage in basispoints (e.g., 5000 = 5%)
}
// Withdraw accumulated royalty based on share ownership
function withdrawRoyalty(uint256 trackId) public {
Track storage track = tracks[trackId];
uint256 ownerShares = track.shareOwnership[msg.sender];
require(ownerShares > 0, "You do not own any shares of this track");
// Calculate owner's share of the royalty
uint256 ownerPercentage = getOwnerSharePercentage(trackId, msg.sender);
uint256 ownerRoyalty = (track.totalRoyalty * ownerPercentage) / 1e18; // Calculate royalty in basis points
require(ownerRoyalty > 0, "No royalty available for withdrawal");
// Deduct the royalty amount from the track's total royalty
track.totalRoyalty -= ownerRoyalty;
// Transfer the calculated royalty amount to the shareholder
payable(msg.sender).transfer(ownerRoyalty);
emit RoyaltyWithdrawn(trackId, msg.sender, ownerRoyalty);
}
// Check total supply of tracks minted
function totalSupply() public view returns (uint256) {
return _trackCounter.current();
}
// Set royalty information for all NFTs in this contract
function setRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips) public onlyOwner {
_setDefaultRoyalty(_receiver, _royaltyFeesInBips);
}
// Check supported interfaces for compatibility
function supportsInterface(bytes4 interfaceId)
public
view
override(ERC721, ERC2981)
returns (bool)
{
return super.supportsInterface(interfaceId);
}
}