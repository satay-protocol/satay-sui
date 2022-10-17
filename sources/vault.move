module satay::vault {
    use sui::object::{Self, UID, ID};
    use sui::transfer::{Self};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Coin};

    /// Any given vault should only accept one unique BASE coin
    /// `SharedVault` is the vault itself, and `VAULT` is the VAULT coin
    struct Vault<phantom BaseCoin> has key {
        id: UID,
        /// The CoinType to be accepted by a particular vault
        base: Balance<BaseCoin>,
        /// capability allowing the reserve to mint and burn VAULT coin
        vault_supply: Supply<Witness<BaseCoin>>,
    }

    /// VaultCoin token witness
    struct Witness<phantom BaseCoin> has drop { }

    /// Represents depositor's share of vault balance
    struct VaultCoin<phantom BaseCoin> has key, store {
        id: UID,
        vault_id: ID,
        balance: Balance<Witness<BaseCoin>>
    }

    /// Initialize a new vault that only accepts BaseCoin
    /// Initialize a new VaultCoin
    public fun new<BaseCoin>(witness: Witness<BaseCoin>, ctx: &mut TxContext) {
        let id = object::new(ctx);
        // Get a treasury cap for the coin put it in the reserve
        let vault_supply = balance::create_supply<Witness<BaseCoin>>(witness);

        // Instead of `move_to`, Sui Move uses the `transfer` API to move objects into global storage.
        // Here, we instantiate the SharedVault object and move it into global storage (write to the blockchain).
        // We use the `share_object` API, which turns the object into a mutable shared object that everyone can access
        // and mutate. For something like a vault, that can be accessed permissionlessly by anyone, this is what we'll
        // utilize.
        // Note: This capability is not yet fully supported in Sui. Below is what the exposed API will look like.
        transfer::share_object(Vault<BaseCoin> {
            id,
            base: balance::zero<BaseCoin>(),
            vault_supply
        });
    }


    /// Deposit a BASE coin into a given vault, and mint and deposit a VAULT coin into the user's account representing
    /// ownership of their stake in the vault.
    public entry fun deposit<BaseCoin>(base: Coin<BaseCoin>, vault: &mut Vault<BaseCoin>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);

        // todo: assert deposit base cointype == vault base cointype

        // Sui Move makes transferring coins incredibly easy. instead of only accepting a u64 for a public entry fun,
        // in Sui you can pass in the actual
        transfer::transfer_to_object(base, vault);
    }

    /// Get an immutable reference to the ID of the pool the LP coin belongs to.
    public fun vault_coin_vault_id<BaseCoin>(self: &VaultCoin<BaseCoin>): &ID {
        &self.vault_id
    }

    /// Returns the balance of the BaseCoin in the vault, as well as the total supply of VaultCoin
    public fun vault_values<BaseCoin>(vault: &Vault<BaseCoin>): (u64, u64) {
        (
            balance::value(&vault.base),
            balance::supply_value(&vault.vault_supply)
        )
    }
}