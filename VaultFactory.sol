// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract VaultFactory is Ownable, ERC721Holder {
    enum State { inactive, activeOffer }
    using Counters for Counters.Counter;
    // uint256 minOfferTime = 3 days;

    struct Vault {
        address collection;
        uint256 tokenId;
        address owner;
        address fractionalTokenAddress;
        State sellingState;
        uint256 offerPrice; // Offered price for a certian percentage of the shares
        uint256 offerTime;
        uint256 offerPercentage;  // Percentage of shares offered for sale
        address offerBuyer;  // Buyer who made the offer
        mapping(address => uint256) acceptedOffers; // Store who accepted the offer and how much they accepted
        uint256 totalAcceptedShares; // Track the total shares accepted for sale
        address [] tokenHolders;  // Array to keep track of token holders
    }

    mapping(uint256 => Vault) public vaults;
    Counters.Counter public vaultCounter;
    uint256 private constant royaltyPercentage = 10; // 10% royalty

    event VaultCreated(uint256 indexed vaultId , address collection, uint256 tokenId, address owner);
    event OfferMade(uint256 indexed vaultId, uint256 offerPercentage, address offerBuyer);
    event OfferAccepted(uint256 indexed vaultId, uint256 totalPaid);

    constructor() Ownable(msg.sender) {}

    // Function to create a vault, lock the NFT and fractionalize the NFT into ERC20 tokens
    function createVault(
        string memory _name,
        string memory _symbol,
        address _collection,
        uint256 _tokenId
    ) external onlyOwner {
        vaultCounter.increment();  // Start indexing from 1
        uint256 newVaultId = vaultCounter.current();
        address _owner = IERC721(_collection).ownerOf(_tokenId);

        // Transfer the NFT to the contract
        IERC721(_collection).safeTransferFrom(_owner, address(this), _tokenId);

       // Initialize the vault
        Vault storage newVault = vaults[newVaultId];
        newVault.collection = _collection;
        newVault.tokenId = _tokenId;
        newVault.owner = _owner;

        // Deploy the ERC20 contract for fractional tokens
        FractionalToken fractionalToken = new FractionalToken(_name, _symbol, 1250 * 10 ** 18, _owner, newVaultId, address(this),owner());
        newVault.fractionalTokenAddress = address(fractionalToken);

        emit VaultCreated(newVaultId, _collection, _tokenId, msg.sender);
    }

    // Function to make an offer to buy a percentage of the vault's fractional tokens
    // From frontend the percentage will be checked and decided
    function makeOffer(uint256 vaultId, uint256 percentage, uint256 _offerTime) external payable {
        Vault storage vault = vaults[vaultId];
        // require(30 days >= _offerTime && _offerTime >= 3 days );
        require(vault.sellingState == State.inactive, "Vault already had an active offer");
        require(msg.value > 0, "Offer amount must be greater than zero");

        // Set the offer details
        vault.offerPercentage = percentage;
        vault.offerBuyer = msg.sender;
        vault.offerTime = block.timestamp + _offerTime;
        vault.sellingState = State.activeOffer;
        vault.offerPrice = msg.value;

        emit OfferMade(vaultId, percentage, msg.sender);
    }

    //If "true" then there are available shares to accept and "availableSharesToAccept" is the amount of available shares to accept
    function checkAvailableSharesToAccept (uint256 vaultId) public view returns (uint256, bool){
        Vault storage vault = vaults[vaultId];
        uint256 totalSupply = FractionalToken(vault.fractionalTokenAddress).totalSupply();
        uint256 offerShares = (totalSupply * vault.offerPercentage) / 100;
        if (vault.totalAcceptedShares >= offerShares) {
            return (0, false);
        }
        uint256 availableSharesToAccept = offerShares - vault.totalAcceptedShares;
        return (availableSharesToAccept, true);
    }

    // Function for ERC20 token holders to accept the offer and transfer their tokens to the vault
    function acceptOffer(uint256 vaultId, uint256 amountOfShares) external {
        Vault storage vault = vaults[vaultId];
        require(block.timestamp < vault.offerTime, "Offer was ended");
        require(
            FractionalToken(vault.fractionalTokenAddress).allowance(msg.sender, address(this)) == amountOfShares &&
            FractionalToken(vault.fractionalTokenAddress).allowance(msg.sender, address(this)) > 0,
            "Insufficient allowance to transfer tokens"
        );

        uint256 totalSupply = FractionalToken(vault.fractionalTokenAddress).totalSupply();
        uint256 offerShares = (totalSupply * vault.offerPercentage) / 100;

        require(vault.totalAcceptedShares +  amountOfShares <= offerShares, "Please! check the available amount to accept");

        // Transfer tokens from the holder to the vault
        FractionalToken(vault.fractionalTokenAddress).transferFrom(msg.sender, address(this), amountOfShares);

        // Track the accepted shares and amount transferred
        vault.acceptedOffers[msg.sender] = amountOfShares;
        vault.totalAcceptedShares += amountOfShares;
        
        // Adding the offerAccepters address
        vault.tokenHolders.push(msg.sender);

        emit OfferAccepted(vaultId, vault.totalAcceptedShares);
    }

    // Once the offer time is completed & all the transfers will occur in this function
    function endOffer(uint256 vaultId) external {
        Vault storage vault = vaults[vaultId];
        require(block.timestamp > vault.offerTime, "Offer is stil active");

        FractionalToken fractionalToken = FractionalToken(vault.fractionalTokenAddress);

        address buyer = vault.offerBuyer;
        uint256 totalSupply = fractionalToken.totalSupply();
        uint256 offerShares = (totalSupply * vault.offerPercentage) / 100;

        if(vault.totalAcceptedShares < offerShares){
            payable(buyer).transfer(vault.offerPrice);  // Send the offered price back to to offerer/buyer

            for (uint256 i=0; i<vault.tokenHolders.length; i++) {
                address holder = vault.tokenHolders[i];
                // Check if the holder has accepted any offers
                uint256 amountAccepted = vault.acceptedOffers[holder];
                if (amountAccepted == 0) {
                    continue;
                }
                else{
                    // Transfer the accepted tokens back to the holder
                    fractionalToken.transfer(holder, amountAccepted);
                    vault.acceptedOffers[holder] = 0;
                }
            }     
        }

        else {
            // Transfer accepted shares to the buyer
            fractionalToken.transfer(buyer, offerShares);
             //royalty
            //uint256 offerprice=vault.offerPrice;
            uint256 royaltyamnt=vault.offerPrice/10;
            uint256 remainingOfferPrice=vault.offerPrice-royaltyamnt;
            payable (owner()).transfer(royaltyamnt);

            // uint256 remainingShares = vault.totalAcceptedShares - offerShares;
            uint256 tokenPrice = remainingOfferPrice * 10**18 / offerShares;
            // uint256 payablePercentage = offerShares * 10**18 / vault.totalAcceptedShares;
            // uint256 redundentSharePercentage = remainingShares * 10**18 / vault.totalAcceptedShares;

            for (uint256 i=0; i<vault.tokenHolders.length; i++) {
                address holder = vault.tokenHolders[i];

                // Check if the holder has accepted any offers
                uint256 amountAccepted = vault.acceptedOffers[holder];
                if (amountAccepted == 0) {
                    continue;
                }
                else{
                    // uint256 payableAmount = (amountAccepted * payablePercentage * tokenPrice) / 10**36; //Token holder will receive this amount
                    uint256 payableAmount = (amountAccepted * tokenPrice) / 10**18; //Token holder will receive this amount
                    
                    //Send the offered amount payout to the tokenholders
                    payable(holder).transfer(payableAmount);

                    // Transfer the accepted tokens back to the holder
                    // fractionalToken.transfer(holder, (amountAccepted * redundentSharePercentage) / 10**18);
                    vault.acceptedOffers[holder] = 0;
                }
            } 
        }

        // Clear the vault's offer data
        vault.offerPercentage = 0;
        vault.offerBuyer = address(0);
        vault.totalAcceptedShares = 0;
        vault.offerTime = 0;
        vault.offerPrice = 0;
        vault.sellingState == State.inactive;
    }

    // // To get the the vault's Information
    // function getVaultInfo(uint256 vaultId) public view returns (State, uint256, uint256, uint256) {
    //     Vault storage vault = vaults[vaultId];
    //     return (vault.sellingState, vault.offerTime, vault.totalAcceptedShares, vault.offerPercentage);  // We can return other needed fields as well **like (... , .... , ...)
    // }
}

contract FractionalToken is ERC20, ERC20Permit {

    uint256 internal vaultId;
    address internal vaultAddress;

    struct SellOffer {
        address seller;
        uint256 amount;    // Amount of tokens offered
        uint256 price;     // Price per token in Wei
    }
    uint256 private activeSellingOffers;

    address[] public tokenHolders;
    address public royaltyOwner;


    mapping(address => SellOffer) public sellOffers;  // Track address to store sell offers

    event TokensListedForSale(address indexed seller, uint256 amount, uint256 price);
    event SellOfferCanceled(address indexed seller, uint256 amount);
    event TokensPurchased(address indexed buyer, address indexed seller, uint256 amount, uint256 totalCost);

    constructor(string memory name, string memory symbol, uint256 totalSupply, address _to, uint256 _vaultId, address _vaultAddress,address rOwner)
        ERC20(name, symbol) ERC20Permit(name) {
        _mint(_to, totalSupply);
        vaultId = _vaultId;
        vaultAddress = _vaultAddress;
        royaltyOwner=rOwner;
    }

    // // This function approves the vault to be the spender and calls the acceptOffer function

    // function vaultApproval(address spender, uint256 value) public {
    //     // Get the VaultFactory contract instance
    //     VaultFactory vaultFactory = VaultFactory(vaultAddress);

    //     // Get the current state and offerTime of the vault from the VaultFactory
    //     (VaultFactory.State vaultState, uint256 offerTime, uint256 totalAcceptedShares, uint256 offerPercentage) = vaultFactory.getVaultInfo(vaultId);
        
    //     uint256 totalSupply = totalSupply();
    //     uint256 offerShares = (totalSupply * offerPercentage) / 100;

    //     // Ensure the vault is in the correct state
    //     require(vaultState == VaultFactory.State.activeOffer, "Vault is not in an active offer state");
    //     require(block.timestamp < offerTime, "Offer time has ended");
    //     require(totalAcceptedShares >= offerShares, "Offer amount is already accepted");

    //     // Approve the `spender` to transfer tokens
    //     approve(spender, value);

    //     // Accept the offer by calling acceptOffer on the VaultFactory contract
    //     vaultFactory.acceptOffer(vaultId, value);
    // }

    // function approve(address spender, uint256 value) public override returns (bool) {
    //     _approve(msg.sender, spender, value);
    //     return true;
    // }

    // ------------------- Selling Functionality -----------------------

    /* 
    Allows a shareholder to list tokens for sale at a specified price
    _amount The number of tokens to sell.
    _price The price per token the seller wants to sell for. */

    function sellTokens(uint256 _amount, uint256 _price) external { 
        require(balanceOf(msg.sender) >= _amount &&
        balanceOf(msg.sender) > 0 , "Insufficient balance to sell");
        SellOffer storage selloffer = sellOffers[msg.sender];

        // Already listed as seller
        if (selloffer.amount>0) {
            selloffer.amount += _amount;
            selloffer.price = _price;

            // Transfer tokens to contract to hold them in escrow for sale
            _transfer(msg.sender, address(this), _amount);

            emit TokensListedForSale(msg.sender, selloffer.amount + _amount, _price);

        }
        //Listed as seller for the first time
        else {
            // Transfer tokens to contract to hold them in escrow for sale
            _transfer(msg.sender, address(this), _amount);

            // Create a new sell offer
            sellOffers[msg.sender] = SellOffer(msg.sender, _amount, _price);
            activeSellingOffers++;

            // Adding the tokenHolder address
            tokenHolders.push(msg.sender);

            emit TokensListedForSale(msg.sender, _amount, _price);
        }
        
    }

    /*
    Allows a seller to cancel their sell offer.
    offerId The ID of the sell offer to cancel. */

    function cancelSellOffer() external {
        require(sellOffers[msg.sender].seller == msg.sender, "Not the seller of this offer");

        // Return tokens to the seller
        _transfer(address(this), msg.sender, sellOffers[msg.sender].amount);
        activeSellingOffers--;

        emit SellOfferCanceled(msg.sender, sellOffers[msg.sender].amount);

        // Delete the offer
        delete sellOffers[msg.sender];
    }

    // ------------------- Buying Functionality -----------------------
       
    /*
    Allows a buyer to purchase tokens from the available sell offers, they can check all the avaiable offers and choose one
    _seller The address of the seller who has listed their tokens for sale.
    Allows a buyer to purchase tokens from the available sell offers, starting with the lowest price. */

    function buyTokens(address _seller) external payable {
        uint256 totalTransferableToken = (msg.value * 10 ** 18) / sellOffers[_seller].price; // Previously it was _amount ** purchasing token amount 
        uint256 totalPayable = msg.value; // the total amount of the sold tokens in matic

        // Check to see if msg.value is greater than 0
        require(totalPayable >= 0, "Insufficient funds");

        require(totalTransferableToken <= sellOffers[_seller].amount, "Enter a valid amount");
        uint royalty=totalPayable/10;
        uint remainingAmnt=totalPayable-royalty;

        //  Transfer tokens from contract to the buyer
        _transfer(address(this), msg.sender, totalTransferableToken);
        sellOffers[_seller].amount -= totalTransferableToken;

        // Pay the seller the total amount for the sold tokens
         // Pay the seller the total amount for the sold tokens
        payable (royaltyOwner).transfer(royalty);
        payable(_seller).transfer(remainingAmnt);


        // Delete the seller details who has sold all his tokens
        if (sellOffers[_seller].amount == 0) {
            delete sellOffers[_seller];
            activeSellingOffers--;
        }

        // Adding the tokenHolder address (new buyer)
        tokenHolders.push(msg.sender);

        // Emit an event for successful token purchase
        emit TokensPurchased(msg.sender, sellOffers[_seller].seller, totalTransferableToken, totalPayable);
    }

    // ------------------- Gifting Functionality -----------------------
    // Not needed just need to transfer the tokens

    // ------------------- Utility Functions -----------------------

    /*
    Gets the total number of sell offers. */

    function getTotalSellOffers() public view returns (uint256) {
        return activeSellingOffers;
    }

    /**
    Gets the details of a sell offer.
    @return seller Address of the seller
    @return amount Amount of tokens for sale
    @return price Price per token in Wei */

    function getSellOffer(uint256 num) public view returns (address seller, uint256 amount, uint256 price) {
       SellOffer storage s = sellOffers[tokenHolders[num]];
       return (s.seller, s.amount, s.price);
    }

    // Function to burn tokens
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}