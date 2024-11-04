// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC721VaultFactory is Ownable, ERC721Holder {
    using Counters for Counters.Counter;

    struct Vault {
        string name;
        string symbol;
        address collection;
        uint256 tokenId;
        address owner;
        address fractionalTokenAddress;
        bool isLocked;
        bool forSale;
        uint256 salePrice;
        address[] tokenHolders; // Array to keep track of token holders
        address[] previousOwner;
    }

    mapping(uint256 => Vault) public vaults;
    Counters.Counter public vaultCounter;
    uint256 public royaltyPercentage = 5; // 5% of royalty

    event VaultCreated(uint256 vaultId, address collection, uint256 tokenId, address owner);
    event Fractionalized(uint256 vaultId, address owner, uint256 totalShares);
    event Defractionalized(uint256 vaultId, address owner);

    constructor() Ownable(msg.sender) {}

    // added onlyowner function
    function createVault(
        string memory _name,
        string memory _symbol,
        address _collection,
        uint256 _tokenId,
        uint256 _sellingPrice
    ) external onlyOwner {
        vaultCounter.increment();
        uint256 newVaultId = vaultCounter.current();
        address _owner = IERC721(_collection).ownerOf(_tokenId);

        IERC721(_collection).safeTransferFrom(_owner, address(this), _tokenId);

        vaults[newVaultId] = Vault({
            name: _name,
            symbol: _symbol,
            collection: _collection,
            tokenId: _tokenId,
            owner: _owner,
            fractionalTokenAddress: address(0),
            isLocked: true,
            forSale: false,
            salePrice: 0,
            tokenHolders: new address [](0), // Initialize empty array for token holders
            previousOwner: new address [] (0) // Initialize empty array for NFT holders
        });
        fractionalizeVault(newVaultId, 1250 * 10 ** 18, _owner, _sellingPrice);

        emit VaultCreated(newVaultId, _collection, _tokenId, msg.sender);
    }

    function fractionalizeVault(uint256 vaultId, uint256 _totalShares, address _to, uint256 sellingPrice) internal onlyOwner {
        Vault storage vault = vaults[vaultId];

        // Deploy the ERC20 contract for fractional tokens
        FractionalToken fractionalToken = new FractionalToken(vault.name, vault.symbol, _totalShares, _to);
        vault.fractionalTokenAddress = address(fractionalToken);

        // Adding the tokenHolder address
        vault.tokenHolders.push(_to);

        putForSale(vaultId, sellingPrice);

        emit Fractionalized(vaultId, msg.sender, _totalShares);
    }

    // Selling function

    function putForSale(uint256 vaultId, uint256 price) public {
        Vault storage vault = vaults[vaultId];
        require(!vault.forSale, "Already up for sale");
        address _owner = owner();
        require (_owner == msg.sender || vault.owner == msg.sender, "You are not the owner");
        
        if (vault.owner == msg.sender) {
            IERC721 nft = IERC721(vault.collection);
            require (nft.getApproved(vault.tokenId) == address(this), "Not approved, Please! give approval first");
            IERC721(vault.collection).safeTransferFrom(msg.sender, address(this), vault.tokenId);
            vault.salePrice = price;
            vault.isLocked = true;
            vault.forSale = true;
        }
        else {
            vault.salePrice = price;
            vault.forSale = true;
        }
    }

    // Set the royalty percentage
    function setRoyaltyToken(uint256 _percentage) external onlyOwner {
        royaltyPercentage = _percentage;
    }

    // ERC20 token transfering method ** with approval
    function tokenTransferFrom (uint256 vaultId, address _from, address _to, uint256 amount) public {
        Vault storage vault = vaults[vaultId];
        IERC20(vault.fractionalTokenAddress).transferFrom(_from, _to, amount);
        
        // Adding the tokenHolder address
        vault.tokenHolders.push(_to);
    }

    // ERC20 token transfering method by the token owners
    function tokenTransfer (uint256 vaultId, address _to, uint256 amount) public {
        Vault storage vault = vaults[vaultId];
        FractionalToken(vault.fractionalTokenAddress)._tokenTransfer(msg.sender, _to, amount);
        
        // Adding the tokenHolder address
        vault.tokenHolders.push(_to);
    }

    // ERC20 token spender approval
    function tokenApproval (uint256 vaultId, address _spender, uint256 amount) public {
        Vault storage vault = vaults[vaultId];
        address _owner = msg.sender;
        require(IERC20(vault.fractionalTokenAddress).balanceOf(_owner) >= amount, "You do not have enough tokens");
        FractionalToken(vault.fractionalTokenAddress)._tokenApproval(_owner, _spender, amount);
    }

    // ERC20 token spender permit approval
    function tokenPermit (uint256 vaultId, address _spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        Vault storage vault = vaults[vaultId];
        address _owner = msg.sender;
        require(IERC20(vault.fractionalTokenAddress).balanceOf(_owner) >= amount, "You do not have enough tokens");
        FractionalToken(vault.fractionalTokenAddress)._tokenPermit(_owner, _spender, amount, deadline, v, r, s);
    }

    //To change the selling price only NFT owner function
    function updateSellingPrice (uint256 vaultId, uint256 price) public {
        Vault storage vault = vaults[vaultId];
        require(!vault.forSale, "Already up for sale");
        require (vault.owner == msg.sender, "You are not the owner");
        vault.salePrice = price;
    }

    function purchase (uint256 vaultId) external payable {
        Vault storage vault = vaults[vaultId];
        require(vault.isLocked, "Vault is not locked");
        require(vault.forSale, "Not for sale");
        require(msg.value >= vault.salePrice, "Insufficient funds");
        
        // Store the current buyer's address in previousOwner array
        vault.previousOwner.push(vault.owner);

        // Transfer the NFT to the buyer
        IERC721(vault.collection).safeTransferFrom(address(this), msg.sender, vault.tokenId);
        vault.owner = msg.sender;
        vault.forSale = false;
        vault.isLocked = false;

        // Automatically redeem shares for previous holders
        uint256 totalEther = address(this).balance;
        uint256 totalSupply = IERC20(vault.fractionalTokenAddress).totalSupply();
        
        // Automatically share and royalty holders will get redeemable amount by this loop
        for (uint256 i = 0; i < vault.tokenHolders.length; i++) {
            address tokenHolder = vault.tokenHolders[i];
            uint256 balance = IERC20(vault.fractionalTokenAddress).balanceOf(tokenHolder);
            uint256 amountToRedeem = (balance * totalEther) / totalSupply;

            // Transfer fractional tokens to vault owner
            FractionalToken(vault.fractionalTokenAddress)._tokenTransfer(tokenHolder, vault.owner, balance);

            // Send Ether equivalent to the fractional shares to the previous holder
            (bool sent, ) = payable(tokenHolder).call{value: amountToRedeem}("");
            require(sent, "Failed to send Ether");
        }

        // Automatically share price will be redeemed by this loop
        uint256 royaltyAmount = (totalSupply * royaltyPercentage) / 100;

        for (uint256 i = 0; i < vault.previousOwner.length; i++) {
            address royaltyReceivers = vault.previousOwner[i];
            FractionalToken(vault.fractionalTokenAddress)._tokenTransfer(vault.owner, royaltyReceivers, royaltyAmount);
        }

        // Adding the tokenHolder address
        vault.tokenHolders.push(vault.owner);
    }

    function _totalSupply(uint256 vaultId) external view returns (uint256){
        Vault storage vault = vaults[vaultId];
        return IERC20(vault.fractionalTokenAddress).totalSupply();
    }

    function _balanceOf(uint256 vaultId, address account) external view returns (uint256) {
        Vault storage vault = vaults[vaultId];
        return IERC20(vault.fractionalTokenAddress).balanceOf(account);
    }
}

contract FractionalToken is ERC20, Ownable, ERC20Permit {

    constructor(string memory name, string memory symbol, uint256 totalSupply, address _to)
        ERC20(name, symbol) ERC20Permit(name) Ownable (msg.sender){
        _mint(_to, totalSupply);
    }

    function _tokenTransfer(address owner, address to, uint256 value) external {
        _transfer(owner, to, value);
    }

    function _tokenPermit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        permit (owner, spender, value, deadline, v, r, s);
    }

    function _tokenApproval(address owner, address spender, uint256 value) external {
        _approve(owner, spender, value);
    }
}