module satay::vault {
    use sui::object::{Self, UID, ID};
    use sui::transfer::{Self};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin};

    /* ================= Errors ================= */

    /// For when the Coin balance is too low.
    const EInsufficientBalance: u64 = 0;

    /* ================= Vault ================= */

    /// A given vault should only accept one unique BaseCoin
    struct Vault<phantom BaseCoin> has key {
        id: UID,
        /// The CoinType to be accepted by a particular vault
        basecoin_balance: Balance<BaseCoin>,
        /// capability allowing the reserve to mint and burn VaultCoins
        vaultcoin_supply: Supply<VaultCoinWitness<BaseCoin>>,
    }

    /// Get an immutable reference to the ID of the vault the VaultCoin belongs to.
    public fun vaultcoin_vault_id<BaseCoin>(self: &VaultCoin<BaseCoin>): &ID {
        &self.vault_id
    }

    /// Returns the balance of the BaseCoin in the vault, as well as the total supply of VaultCoin
    public fun vault_values<BaseCoin>(vault: &Vault<BaseCoin>): (u64, u64) {
        (
            balance::value(&vault.basecoin_balance),
            balance::supply_value(&vault.vaultcoin_supply)
        )
    }

    /* ================= VaultCoin ================= */

    /// VaultCoin token witness
    /// Witness is a pattern that is used for confirming the ownership of a type. To do so, one passes a drop instance
    /// of a type. Coin relies on this implementation. https://examples.sui.io/patterns/witness.html
    struct VaultCoinWitness<phantom BaseCoin> has drop { }

    /// Represents depositor's share of vault balance
    struct VaultCoin<phantom BaseCoin> has key, store {
        id: UID,
        vault_id: ID,
        balance: Balance<VaultCoinWitness<BaseCoin>>
    }

    /* ================= PoolAdminCap ================= */

    /// Capability that grants the vault admin the right to collect mangagement and performance fees.
    struct VaultAdminCap has key, store {
        id: UID,
        vault_id: ID
    }

    /// Get the reference to the pool ID this capabilty belongs to.
    public fun admin_cap_pool_id(cap: &VaultAdminCap): &ID {
        &cap.vault_id
    }

    /* ================= Main logic ================= */

    /* ================= public entry functions ================= */

    /// Initialize a new vault that only accepts BaseCoin
    /// Initialize a new VaultCoin
    entry fun new<BaseCoin>(
        ctx: &mut TxContext
    ) {
        let witness = VaultCoinWitness<BaseCoin> {};
        let id = object::new(ctx);
        // Get a treasury cap for the coin put it in the reserve
        let vaultcoin_supply = balance::create_supply<VaultCoinWitness<BaseCoin>>(witness);

        // Transfer the AdminCap to the sender (the user calling this function)
        transfer::transfer(VaultAdminCap {
            id: object::new(ctx),
            vault_id: object::uid_to_inner(&id),
        }, tx_context::sender(ctx));

        // Instead of `move_to`, Sui Move uses the `transfer` API to move objects into global storage.
        // Here, we instantiate the Vault object and move it into global storage (write to the blockchain).
        // We use the `share_object` API, which turns the object into a mutable shared object that everyone can access
        // and mutate. For something like a vault that can be accessed permissionlessly by anyone, this is what we'll
        // utilize. Note: This capability is not yet fully supported in Sui. Below is what the exposed API will look like.
        transfer::share_object(Vault<BaseCoin> {
            id,
            basecoin_balance: balance::zero<BaseCoin>(),
            vaultcoin_supply
        });
    }

    // As opposed to Aptos, where you can only pass in scalar values (u64, address, vector, etc) in public entry funs,
    // Sui Move allows for unique object types to be passed in (i.e. the Coin and Vault object types below). Instead of
    // then using `borrow_global_mut` to access the CoinType (BaseCoin), the CoinType can be passed in directly into
    // the function signature.
    /// Deposit a BaseCoin into a given vault, and mint and deposit a VaultCoin into the user's account representing
    /// ownership of their stake in the vault.
    public entry fun deposit<BaseCoin>(
        amount: u64,
        basecoin: &mut Coin<BaseCoin>,
        vault: &mut Vault<BaseCoin>,
        ctx: &mut TxContext
    ) {
        // Assert that the user has at least as much BaseCoin in their balance as they want to deposit
        assert!(coin::value(basecoin) >= amount, EInsufficientBalance);

        // Take the `amount` of BaseCoin from the depositor and transfer it to `vault.basecoin_balance`
        let basecoin_balance = coin::balance_mut(basecoin);
        let deposit_amt = balance::split(basecoin_balance, amount);
        balance::join(&mut vault.basecoin_balance, deposit_amt);

        // Mint and deposit VaultCoin<BaseCoin> to the sender's address
        mint_and_deposit_vaultcoin(vault, amount, ctx);
    }

    public entry fun withdraw<BaseCoin>(
        amount: u64,
        vaultcoin: &mut Coin<VaultCoin<BaseCoin>>,
        vault: &mut Vault<BaseCoin>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Assert that the user cannot withdraw more BaseCoin than they have VaultCoin
        // let vaultcoin_balance = coin::balance(vaultcoin);
        assert!(coin::value<VaultCoin<BaseCoin>>(vaultcoin) >= amount, EInsufficientBalance);

        // Transfer BaseCoin from the vault to the user
        let basecoin_value = balance::value(&mut vault.basecoin_balance);
        let temp = balance::split(&mut vault.basecoin_balance, basecoin_value);
        transfer::transfer(
            coin::from_balance<BaseCoin>(temp, ctx),
            sender
        );
        
        // Burn the equivalent amount of VaultCoin from the user's balance
        // let VaultCoin<BaseCoin> { id, vault_id: _, balance: vaultcoin.balance} = vaultcoin;
        // object::delete(id);
        // balance::decrease_supply(&mut vault.vaultcoin_supply,)
    }

    /* ================= helper functions ================= */

    fun mint_and_deposit_vaultcoin<BaseCoin>(
        vault: &mut Vault<BaseCoin>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        let vaultcoin_minted = balance::increase_supply(&mut vault.vaultcoin_supply, amount);

        let vaultcoin = VaultCoin<BaseCoin> {
            id: object::new(ctx),
            vault_id: object::uid_to_inner(&vault.id),
            balance: vaultcoin_minted,
        };

        transfer::transfer(vaultcoin, sender);
    }

}