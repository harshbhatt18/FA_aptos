module vangogh::fungibleAsset{

    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use std::error;
    use std::signer;
    use std::string::utf8;
    use std::option;

    const ENOT_OWNER: u64 = 1;
    const EPAUSED: u64 = 2;
    const ASSET_SYMBOL: vector<u8> = b"HSB";

   

    /* This line tells Aptos that ManagedFungibleAsset belongs to a group of resources
     that can be stored together in the same storage location on chain.
     ObjectGroup is a standard group in Aptos for storing object-related data efficiently.*/
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /*ManagedFungibleAsset stores the references needed to manage a fungible asset:
    - mint_ref: Allows minting new tokens of this asset
    - transfer_ref: Allows configuring transfer rules and restrictions
    - burn_ref: Allows burning (destroying) tokens of this asset
    These refs provide full control over the asset's lifecycle and can only be 
    accessed by the asset creator/admin.*/
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /* State struct tracks the operational status of the fungible asset:
    - paused: When true, certain operations like transfers may be restricted
    The struct has the 'key' ability so it can be stored in global storage*/
    struct State has key {
        paused: bool,
    }

   
    /* Initializes a new fungible asset with the following:
    - Creates a named object for the fungible asset using ASSET_SYMBOL
    - Creates a primary store enabled fungible asset with metadata.
    - Generates mint, burn and transfer references for asset management
    - Stores the references in ManagedFungibleAsset resource
    - Initializes State resource with paused=false*/
    fun init_module(admin: &signer) {
        let constructor_ref = &object::create_named_object(admin, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(b"HSB Token"), 
            utf8(ASSET_SYMBOL),
            18,
            utf8(b""),
            utf8(b"")
        );

        // Generate references that allow the owner/creator to manage the fungible asset
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);      // For minting new tokens
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);      // For burning tokens
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref); // For transferring tokens
        
        let metadata_object_signer = object::generate_signer(constructor_ref);
        
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
        );

        move_to(
            &metadata_object_signer,
            State { paused: false, }
        );    
    }

    #[view]
    /// Returns the metadata object for this fungible asset
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&@vangogh, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    /// Returns the token balance for the given address by looking up their primary store
    public fun get_balance(address: address): u64 {
        let asset = get_metadata();
        primary_fungible_store::balance(address, asset)
    }

    /* This function mints new fungible assets and deposits them to a specified address
    It requires the ManagedFungibleAsset resource to access minting capabilities
    
    Flow:
    1. Gets metadata object for the fungible asset
    2. Borrows immutable references to mint/transfer capabilities after authorization
    3. Ensures destination has a primary store, creating if needed
    4. Mints new tokens using mint reference
    5. Deposits minted tokens using transfer reference
    
    Parameters:
    - admin: &signer - Admin signer reference for authorization checks
    - to: address - Destination address to receive minted tokens  
    - amount: u64 - Amount of tokens to mint
    
    Note: All references are immutable since we only need to read the capabilities,
    not modify them. The actual token creation and movement happens through the
    capability references rather than direct mutation.*/
    public entry fun mint(admin: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let managed_fungible_asset = authorized_borrow_refs(admin, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
    }

    
    /* This function transfers fungible assets between two addresses
    It requires the ManagedFungibleAsset resource to access transfer capabilities
    
    Flow:
    1. Gets metadata object for the fungible asset
    2. Borrows immutable reference to transfer capability after authorization
    3. Gets source wallet primary store
    4. Ensures destination has a primary store, creating if needed
    5. Withdraws tokens from source using transfer reference
    6. Deposits withdrawn tokens to destination using transfer reference
    
    Parameters:
    - admin: &signer - Admin signer reference for authorization checks
    - from: address - Source address to withdraw tokens from
    - to: address - Destination address to deposit tokens to
    - amount: u64 - Amount of tokens to transfer
    
    Note: All references are immutable since we only need to read the capabilities and stores,
    not modify them directly. The actual token movement happens through the
    capability reference rather than direct mutation.*/
    public entry fun transfer(admin: &signer, from: address, to: address, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::withdraw_with_ref(transfer_ref, from_wallet, amount);
        fungible_asset::deposit_with_ref(transfer_ref, to_wallet, fa);
    }

    /* This function burns (destroys) fungible assets from an address
    It requires the ManagedFungibleAsset resource to access burn capabilities
    
    Flow:
    1. Gets metadata object for the fungible asset
    2. Borrows immutable reference to burn capability after authorization
    3. Gets source wallet primary store
    4. Burns tokens from source using burn reference
    
    Parameters:
    - admin: &signer - Admin signer reference for authorization checks
    - from: address - Source address to burn tokens from
    - amount: u64 - Amount of tokens to burn
    
    Note: All references are immutable since we only need to read the capabilities and stores,
    not modify them directly. The actual token destruction happens through the
    capability reference rather than direct mutation.*/
    public entry fun burn(admin: &signer, from: address, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let burn_ref = &authorized_borrow_refs(admin, asset).burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);
    }
   
    /* This inline function performs authorization checks and borrows references to fungible asset capabilities
    
    Parameters:
    - owner: &signer - The signer attempting to access the capabilities
    - asset: Object<Metadata> - The metadata object representing the fungible asset
    
    Returns:
    - &ManagedFungibleAsset - A reference to struct containing mint/burn/transfer capabilities
    
    This function is marked as inline for performance optimization since it's called frequently.
    It performs two key operations:
    1. Authorization check - Verifies the signer owns the fungible asset metadata
    2. Capability access - Borrows the capabilities if authorized
    
    The inline optimization eliminates function call overhead by embedding the code directly
    at the call site. This is beneficial since this is a security-critical helper used
    in all privileged operations.*/
    inline fun authorized_borrow_refs(
        owner: &signer,
        asset: Object<Metadata>,
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        assert!(object::is_owner(asset, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }


    #[test(owner = @vangogh)]
    /* Tests the basic flow of fungible asset operations:
    1. Initialization: Sets up the module with creator account
    2. Minting: Creates 100 tokens and assigns to creator
    3. Transfer: Sends 50 tokens from creator to drake_address
    4. Burning: Destroys 25 tokens from creator's balance
    
    Flow breakdown:
    - init_module(): Initializes module state and capabilities
    - mint(): Creates 100 new tokens in creator's account
    - Verify creator balance is 100 tokens
    - transfer(): Moves 50 tokens to drake_address
    - Verify drake_address received 50 tokens
    - burn(): Destroys 25 tokens from creator's remaining balance
    - Verify creator has 25 tokens left
    
    The test validates core token operations work correctly:
    - Minting creates correct token amount
    - Transfer moves exact amount between accounts
    - Burning reduces supply appropriately
    - Balances are tracked accurately throughout
    */
    fun test_basic_flow(
        owner: &signer,
    ) acquires ManagedFungibleAsset {
        init_module(owner);
        let owner_address = signer::address_of(owner);
        mint(owner, owner_address, 100);
        let asset = get_metadata();
        assert!(primary_fungible_store::balance(owner_address, asset) == 100, 4);

        let drake_address = @0x123;
        transfer(owner, owner_address, drake_address, 50);
        assert!(primary_fungible_store::balance(drake_address, asset) == 50, 5);

        burn(owner, owner_address, 25);
        assert!(primary_fungible_store::balance(owner_address, asset) == 25, 6);
    }
}
