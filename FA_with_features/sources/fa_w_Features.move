module vangogh::fa_w_Features{
    /*
    FEATURES:
    1. lets add a maxsupply cap for an address to have
    2. lets add a token airdrop feature
    3. lets add whitelisting feature
    */

    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use std::error;
    use std::signer;
    use std::string::utf8;
    use std::option;
    use aptos_framework::table::{Self, Table};

    const ENOT_OWNER: u64 = 1;
    const EPAUSED: u64 = 2;
    const ASSET_SYMBOL: vector<u8> = b"HSB";
    const MAX_SUPPLY_PER_WALLET : u64= 100;
    const EMAX_SUPPLY_PER_WALLET: u64 = 3;
    const ENOT_ENOUGH_BALANCE: u64 = 4;
    const E_NOT_AIRDROP_ACTIVE: u64 = 5;
    const EINVALID_AMOUNT: u64 = 6;
    const EINVALID_LENGTH_MISMATCH: u64 = 7;
    const E_NOT_WHITELIST_ACTIVE: u64 = 8;
    const E_NOT_WHITELISTED: u64 = 9;
    const E_INVALID_ADDRESS_LENGTH: u64 = 10;
    const E_ALREADY_WHITELISTED: u64 = 11;

    const WHITELISTED_ADDRESSES: vector<address> = vector[];

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct State has key {
        paused: bool,
    }

    struct Features has key {
        airdrop_active: bool,
        whitelist_active: bool,
        whitelisted_addresses: Table<address, bool>
    }

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

        move_to(
            &metadata_object_signer,
            Features { airdrop_active: false, whitelist_active: false, whitelisted_addresses: table::new()}
        );
    }

  
    public fun set_features(admin: &signer, airdrop_active: bool, whitelist_active: bool) acquires Features {
        let asset = get_metadata();
        let metadata_address = return_features_address(admin, asset);
        let features = borrow_global_mut<Features>(metadata_address);
        features.airdrop_active = airdrop_active;
        features.whitelist_active = whitelist_active;
    }

    public fun get_features(admin: &signer): (bool, bool) acquires Features {
        let asset = get_metadata();
        let metadata_address = return_features_address(admin, asset);
        let features = borrow_global<Features>(metadata_address);
        (features.airdrop_active, features.whitelist_active)
    }

    public fun is_whitelisted(admin: &signer, address: address): bool acquires Features {
        let asset = get_metadata();
        let metadata_address = return_features_address(admin, asset);
        let features = borrow_global<Features>(metadata_address);
        // Checks if the given address exists as a key in the whitelisted_addresses table
        // Returns true if the address is whitelisted, false otherwise
        table::contains(&features.whitelisted_addresses, address)
    }

    public fun update_whitelisted_address(admin: &signer, address: vector<address>, add:bool) acquires Features {
        assert!(address.length() > 0, E_INVALID_ADDRESS_LENGTH);
        let (_,whitelist_active) = get_features(admin);
        assert!(whitelist_active, E_NOT_WHITELIST_ACTIVE);
        let asset = get_metadata();
        let metadata_address = return_features_address(admin, asset);
        let features = borrow_global_mut<Features>(metadata_address);
        if(add==true){
            for(i in 0..address.length()){
                //revert if the address is already whitelisted
                assert!(!table::contains(&features.whitelisted_addresses, address[i]), E_ALREADY_WHITELISTED);
                table::add(&mut features.whitelisted_addresses, address[i], true);
            }
        } else {
            for(i in 0..address.length()){
                //revert if there is no address to remove
                assert!(table::contains(&features.whitelisted_addresses, address[i]), E_NOT_WHITELISTED);
                table::remove(&mut features.whitelisted_addresses, address[i]);
            }
        }
    }

    #[view]
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&@vangogh, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    public fun get_balance(address: address): u64 {
        let asset = get_metadata();
        primary_fungible_store::balance(address, asset)
    }

   
    public entry fun mint(admin: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
        // This assertion checks if the recipient's balance after minting (current balance + amount to mint)
        // would not exceed the maximum allowed tokens per wallet (MAX_SUPPLY_PER_WALLET).
        // If it would exceed, the transaction fails with EMAX_SUPPLY_PER_WALLET error.
        assert!(get_balance(to) + amount <= MAX_SUPPLY_PER_WALLET, EMAX_SUPPLY_PER_WALLET);

        let asset = get_metadata();
        let managed_fungible_asset = authorized_borrow_refs(admin, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
    }

    
    public entry fun transfer(admin: &signer, from: address, to: address, amount: u64) acquires ManagedFungibleAsset {
        assert!(get_balance(from) >= amount, ENOT_ENOUGH_BALANCE);
        assert!(get_balance(to) + amount <= MAX_SUPPLY_PER_WALLET, EMAX_SUPPLY_PER_WALLET);
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::withdraw_with_ref(transfer_ref, from_wallet, amount);
        fungible_asset::deposit_with_ref(transfer_ref, to_wallet, fa);
    }

    public entry fun burn(admin: &signer, from: address, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let burn_ref = &authorized_borrow_refs(admin, asset).burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);
    }

    /// Airdrop tokens to multiple addresses in a single transaction
    /// @param admin - The signer with admin privileges who can perform the airdrop
    /// @param to - Vector of recipient addresses to receive tokens
    /// @param amount - Vector of token amounts to send to each recipient
    /// Requirements:
    /// - Airdrop feature must be active
    /// - Whitelist feature must be active  
    /// - Length of recipient and amount vectors must match
    /// - Each recipient must be whitelisted
    /// - Each recipient's final balance must not exceed MAX_SUPPLY_PER_WALLET
    /// - Each airdrop amount must be greater than 0
    public entry fun airdropTokens(admin: &signer, to: vector<address>, amount: vector<u64>) acquires ManagedFungibleAsset, Features {
        let (airdrop_active,whitelist_active) = get_features(admin);
        assert!(airdrop_active, E_NOT_AIRDROP_ACTIVE);
        assert!(whitelist_active, E_NOT_WHITELIST_ACTIVE);
        assert!(to.length() == amount.length(), EINVALID_LENGTH_MISMATCH);
        for(i in 0..to.length()) {
            assert!(is_whitelisted(admin, to[i]), E_NOT_WHITELISTED);
            assert!(get_balance(to[i]) + amount[i] <= MAX_SUPPLY_PER_WALLET, EMAX_SUPPLY_PER_WALLET);
            assert!(amount[i] > 0, EINVALID_AMOUNT);
            transfer(admin, signer::address_of(admin), to[i], amount[i]);
        }  
    }
   
    inline fun authorized_borrow_refs(
        owner: &signer,
        asset: Object<Metadata>,
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        assert!(object::is_owner(asset, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }

    inline fun return_features_address(admin: &signer, asset: Object<Metadata>): address acquires Features {
        assert!(object::is_owner(asset, signer::address_of(admin)), error::permission_denied(ENOT_OWNER));
        let metadata_address = object::object_address(&asset);
        assert!(exists<Features>(metadata_address), error::permission_denied(ENOT_OWNER));
        metadata_address
    }

    #[test(owner = @vangogh)]
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

        let result = get_balance(owner_address);
        assert!(result == 25, 7);
    }

    #[test(owner = @vangogh)]
    fun test_airdrop_tokens(
        owner: &signer,
    ) acquires ManagedFungibleAsset, Features {
        init_module(owner);
        let owner_address = signer::address_of(owner);
        mint(owner, owner_address, 100);
        assert!(get_balance(owner_address) == 100, 12);
        set_features(owner, true, true);
        let drake_address = @0x123;
        let drake_address2 = @0x124;
        let drake_address3 = @0x125;
        update_whitelisted_address(owner, vector[drake_address, drake_address2, drake_address3], true);
        airdropTokens(owner, vector[drake_address, drake_address2, drake_address3], vector[10, 10, 10]);
        assert!(get_balance(owner_address) == 70, 8);
        assert!(get_balance(drake_address) == 10, 9);
        assert!(get_balance(drake_address2) == 10, 10);
        assert!(get_balance(drake_address3) == 10, 11);
    }

    #[test(owner = @vangogh)]
    #[expected_failure(abort_code = EMAX_SUPPLY_PER_WALLET)]
    fun test_max_supply_per_wallet(
        owner: &signer,
    ) acquires ManagedFungibleAsset {
        init_module(owner);
        let owner_address = signer::address_of(owner);
        mint(owner, owner_address, 76);
        mint(owner, owner_address, 76); // This should fail since total would exceed MAX_SUPPLY_PER_WALLET because 76+76=152 
        // which is greater than 100
    }

    #[test(owner = @vangogh)]
    #[expected_failure(abort_code = E_NOT_AIRDROP_ACTIVE)]
    fun test_airdrop_not_active(
        owner: &signer,
    ) acquires ManagedFungibleAsset, Features {
        init_module(owner);
        let owner_address = signer::address_of(owner);
        mint(owner, owner_address, 100);
        set_features(owner, false, true);
        let drake_address = @0x123;
        airdropTokens(owner, vector[drake_address], vector[10]);
    }

    #[test(owner = @vangogh)]
    #[expected_failure(abort_code = E_NOT_WHITELIST_ACTIVE)]
    fun test_whitelist_not_active(
        owner: &signer,
    ) acquires ManagedFungibleAsset, Features {
        init_module(owner);
        let owner_address = signer::address_of(owner);
        mint(owner, owner_address, 100);
        set_features(owner, true, false);
        let drake_address = @0x123;
        update_whitelisted_address(owner, vector[drake_address], true);
        airdropTokens(owner, vector[drake_address], vector[10]);
    }

    #[test(owner = @vangogh)]
    #[expected_failure(abort_code = EINVALID_LENGTH_MISMATCH)]
    fun test_invalid_length_mismatch(
        owner: &signer,
    ) acquires ManagedFungibleAsset, Features {
        init_module(owner);
        let owner_address = signer::address_of(owner);
        mint(owner, owner_address, 100);
        set_features(owner, true, true);
        let drake_address = @0x123;
        update_whitelisted_address(owner, vector[drake_address], true);
        airdropTokens(owner, vector[drake_address], vector[10, 10, 10, 10]);
    }

    #[test(owner = @vangogh)]
    #[expected_failure(abort_code = E_NOT_WHITELISTED)]
    fun test_not_whitelisted(
        owner: &signer,
    ) acquires ManagedFungibleAsset, Features {
        init_module(owner);
        let owner_address = signer::address_of(owner);
        mint(owner, owner_address, 100);
        set_features(owner, true, true);
        let drake_address = @0x123;
        airdropTokens(owner, vector[drake_address], vector[10]);
    }
    
}
