/// This module implements methods that create a specific coin type reflecting a
/// foreign asset, whose metadata is encoded in a VAA sent from another network.
///
/// Wrapped assets are created in two steps.
///   1. The coin currency (`CoinMetadata` and `TreasuryCap`) is created by
///      calling `create_unregistered_currency` in another package using the
///      Token Bridge package as a dependency. The `init` method in that package
///      will have the asset metadata VAA hard-coded (which is passed into
///      `create_unregistered_currency` as one of its arguments). `CoinMetadata`
///      is shared and the `TreasuryCap`, encoded VAA and other info is wrapped
///      in an `Unregistered<CoinType>` object. NOTE: To create a new currency,
///      `init` must take a one-time witness (OTW).
///   2. The `Unregistered` object is destroyed as a part of calling
///      `register_new_coin`. This method validates the encoded VAA,
///      deserializes the asset metadata payload and updates `CoinMetadata` to
///      reflect this wrapped asset.
///
/// Wrapped asset metadata can also be updated with a new asset metadata VAA.
/// By calling `update_registered_coin`, Token Bridge verifies that the specific
/// coin type is registered and agrees with the encoded asset metadata's
/// canonical token info. `CoinMetadata` will be updated based on the encoded
/// asset metadata payload.
///
/// References:
/// https://examples.sui.io/basics/one-time-witness.html
module token_bridge::create_wrapped {
    use std::option::{Self};
    use sui::coin::{Self, CoinMetadata, TreasuryCap};
    use sui::object::{Self, UID};
    use sui::transfer::{Self};
    use sui::tx_context::{TxContext};
    use wormhole::state::{State as WormholeState, chain_id};
    use wormhole::vaa::{Self as core_vaa};

    use token_bridge::asset_meta::{Self, AssetMeta};
    use token_bridge::normalized_amount::{max_decimals};
    use token_bridge::state::{Self, State};
    use token_bridge::vaa::{Self};

    /// Asset metadata is for native Sui coin type.
    const E_NATIVE_ASSET: u64 = 0;

    /// Container holding new currency's `TreasuryCap` and other data required
    /// to successfully register a foreign asset.
    struct Unregistered<phantom CoinType> has key, store {
        id: UID,
        vaa_buf: vector<u8>,
        treasury_cap: TreasuryCap<CoinType>
    }

    /// This method is executed within the `init` method of an untrusted module,
    /// which defines a one-time witness (OTW) type (`CoinType`). OTW is
    /// required to call `coin::create_currency` to ensure that only one
    /// `TreasuryCap` exists for `CoinType`. Because the `TreasuryCap` is
    /// managed by Token Bridge's `Unregistered` object, the minting is fully
    /// controlled (i.e. the supply will be zero) by the time
    /// `register_new_coin` is called.
    ///
    /// Placeholder values are used in `CoinMetadata`, which are overwritten in
    /// `register_new_coin`. Because decimals must be determined at the time of
    /// currency creation, this method assumes that `vaa_buf` is an asset meta
    /// VAA (which has the decimal value serialized in its payload).
    ///
    /// Because this method is stateless (i.e. no dependency on Token Bridge's
    /// `State` object), the contract defers VAA verification to
    /// `register_new_coin` after this method has been executed.
    public fun create_unregistered_currency<CoinType: drop>(
        vaa_buf: vector<u8>,
        coin_witness: CoinType,
        ctx: &mut TxContext
    ): Unregistered<CoinType> {
        let payload = core_vaa::peel_payload_from_vaa(&vaa_buf);
        let meta = asset_meta::deserialize(payload);

        let coin_decimals = max_decimals(asset_meta::native_decimals(&meta));

        // Use temporary values for `CoinMetadata`. These will be overwritten
        // when `register_new_coin` is called.
        let (treasury_cap, coin_metadata) =
            coin::create_currency(
                coin_witness,
                coin_decimals,
                b"UNREGISTERED",
                b"Pending Token Bridge Registration",
                b"UNREGISTERED",
                option::none(), // No url necessary.
                ctx
            );

        // We have to share `CoinMetadata` in this method because it cannot be
        // shared later (like in `register_new_coin`).
        transfer::share_object(coin_metadata);

        // Create `Unregistered` object. After execution, this object is
        // typically passed to the publisher of `CoinType`, who will then
        // execute `register_new_coin`.
        Unregistered {
            id: object::new(ctx),
            vaa_buf,
            treasury_cap
        }
    }

    /// After executing `create_unregistered_currency`, user needs to complete
    /// the registration process by calling this method.
    ///
    /// This method destroys `Unregistered<CoinType>`, which warehouses the
    /// asset meta VAA and `TreasuryCap`. These unpacked struc tmmembers are
    /// used to update the symbol and name to what was encoded in the asset meta
    /// VAA payload.
    ///
    /// TODO: Add `UpgradeCap` argument (which would come from the `CoinType`
    /// package so we can either destroy it or warehouse it in `WrappedAsset`.
    public fun register_new_coin<CoinType>(
        token_bridge_state: &mut State,
        worm_state: &mut WormholeState,
        unregistered: Unregistered<CoinType>,
        coin_metadata: &mut CoinMetadata<CoinType>,
        ctx: &mut TxContext,
    ) {
        let Unregistered {
            id,
            vaa_buf,
            treasury_cap,
        } = unregistered;
        object::delete(id);

        // Deserialize to `AssetMeta`.
        let meta =
            parse_and_verify_asset_meta(
                token_bridge_state,
                worm_state,
                vaa_buf,
                ctx
            );

        // `register_wrapped_asset` uses `registered_tokens::add_new_wrapped`,
        // which will check whether the asset has already been registered and if
        // the token chain ID is not Sui's.
        //
        // If both of these conditions are met, `register_wrapped_asset` will
        // succeed and the new wrapped coin will be registered.
        state::register_wrapped_asset(
            token_bridge_state,
            asset_meta::token_chain(&meta),
            asset_meta::token_address(&meta),
            treasury_cap,
            coin_metadata,
        );

        // Proceed to update coin's metadata.
        handle_update_metadata(
            token_bridge_state,
            &meta,
            coin_metadata
        );
    }

    /// For existing wrapped assets, we can update the existing `CoinMetadata`
    /// for a given `CoinType` (one that belongs to Token Bridge's wrapped
    /// registry) with a new asset meta VAA emitted from a foreign network.
    public fun update_registered_metadata<CoinType>(
        token_bridge_state: &mut State,
        worm_state: &mut WormholeState,
        vaa_buf: vector<u8>,
        coin_metadata: &mut CoinMetadata<CoinType>,
        ctx: &mut TxContext
    ) {
        // Deserialize to `AssetMeta`.
        let meta =
            parse_and_verify_asset_meta(
                token_bridge_state,
                worm_state,
                vaa_buf,
                ctx
            );

        // Verify that the registered token info agrees with the info encoded in
        // this transfer.
        let token_chain = asset_meta::token_chain(&meta);
        state::assert_registered_token<CoinType>(
            token_bridge_state,
            token_chain,
            asset_meta::token_address(&meta)
        );
        // Check whether this asset is wrapped may be superfluous, but we want
        // to ensure that this VAA was not generated by this Token Bridge.
        assert!(token_chain != chain_id(), E_NATIVE_ASSET);

        // Proceed to update coin's metadata.
        handle_update_metadata(
            token_bridge_state,
            &meta,
            coin_metadata
        );
    }

    fun parse_and_verify_asset_meta(
        token_bridge_state: &mut State,
        worm_state: &mut WormholeState,
        vaa_buf: vector<u8>,
        ctx: &mut TxContext
    ): AssetMeta {
        let parsed =
            vaa::parse_verify_and_consume(
                token_bridge_state,
                worm_state,
                vaa_buf,
                ctx
            );

        // Finally deserialize the VAA payload.
        asset_meta::deserialize(core_vaa::take_payload(parsed))
    }

    fun handle_update_metadata<CoinType>(
        token_bridge_state: &State,
        meta: &AssetMeta,
        coin_metadata: &mut CoinMetadata<CoinType>,
    ) {
        // We need `TreasuryCap` to grant us access to update the symbol and
        // name for a given `CoinType`.
        let treasury_cap = state::treasury_cap(token_bridge_state);
        coin::update_symbol(
            treasury_cap,
            coin_metadata,
            asset_meta::symbol_to_ascii(meta)
        );

        // Name as UTF-8.
        coin::update_name(
            treasury_cap,
            coin_metadata,
            asset_meta::name_to_utf8(meta)
        );

        // We are using the description of `CoinMetadata` as a convenient spot
        // to preserve a UTF-8 symbol, if it has any characters that are not in
        // the ASCII character set.
        coin::update_description(
            treasury_cap,
            coin_metadata,
            asset_meta::symbol_to_utf8(meta)
        );
    }
}
