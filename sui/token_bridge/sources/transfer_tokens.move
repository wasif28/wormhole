module token_bridge::transfer_tokens {
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use wormhole::external_address::{ExternalAddress};
    use wormhole::state::{State as WormholeState};

    use token_bridge::normalized_amount::{Self, NormalizedAmount};
    use token_bridge::state::{Self, State};
    use token_bridge::transfer::{Self};

    // `transfer_tokens_with_payload` requires `handle_transfer_tokens`.
    friend token_bridge::transfer_tokens_with_payload;

    /// Relayer fee exceeds `Coin` balance.
    const E_TOO_MUCH_RELAYER_FEE: u64 = 0;

    public fun transfer_tokens<CoinType>(
        token_bridge_state: &mut State,
        worm_state: &mut WormholeState,
        bridged: Coin<CoinType>,
        wormhole_fee: Coin<SUI>,
        recipient_chain: u16,
        recipient: ExternalAddress,
        relayer_fee: u64,
        nonce: u32,
    ): u64 {
        let (
            token_chain,
            token_address,
            norm_amount,
            norm_relayer_fee
        ) = handle_transfer_tokens(token_bridge_state, bridged, relayer_fee);

        // Prepare for serialization.
        let transfer = transfer::new(
            norm_amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            norm_relayer_fee,
        );

        // Publish with encoded `Transfer`.
        state::publish_wormhole_message(
            token_bridge_state,
            worm_state,
            nonce,
            transfer::serialize(transfer),
            wormhole_fee,
        )
    }

    /// For a given `CoinType`, prepare outbound transfer.
    ///
    /// This method is also used in `transfer_tokens_with_payload`.
    public(friend) fun handle_transfer_tokens<CoinType>(
        token_bridge_state: &mut State,
        bridged: Coin<CoinType>,
        relayer_fee: u64,
    ): (u16, ExternalAddress, NormalizedAmount, NormalizedAmount) {
        // Disallow `relayer_fee` to be greater than the amount in `Coin`.
        let amount = coin::value(&bridged);
        assert!(relayer_fee <= amount, E_TOO_MUCH_RELAYER_FEE);

        // Either burn or deposit depending on `CoinType`.
        state::take_from_circulation<CoinType>(token_bridge_state, bridged);

        // Fetch canonical token info from registry.
        let (
            token_chain,
            token_address
        ) = state::token_info<CoinType>(token_bridge_state);

        // And decimals to normalize raw amounts.
        let decimals = state::coin_decimals<CoinType>(token_bridge_state);

        (
            token_chain,
            token_address,
            normalized_amount::from_raw(amount, decimals),
            normalized_amount::from_raw(relayer_fee, decimals)
        )
    }
}


#[test_only]
module token_bridge::transfer_token_test {
    use sui::coin::{Self, CoinMetadata, TreasuryCap};
    use sui::sui::{SUI};
    use sui::test_scenario::{
        Self,
        Scenario,
        next_tx,
        return_shared,
        take_shared,
        take_from_address,
        num_user_events,
        ctx
    };
    use wormhole::external_address::{Self};
    use wormhole::state::{State as WormholeState};

    use token_bridge::bridge_state_test::{
        set_up_wormhole_core_and_token_bridges
    };
    use token_bridge::create_wrapped::{Self, Unregistered};
    use token_bridge::wrapped_coin_12_decimals::{Self, WRAPPED_COIN_12_DECIMALS};
    use token_bridge::native_coin_10_decimals::{Self, NATIVE_COIN_10_DECIMALS};
    use token_bridge::state::{Self, State};
    use token_bridge::transfer_tokens::{
        E_TOO_MUCH_RELAYER_FEE,
        transfer_tokens,
    };

    fun scenario(): Scenario { test_scenario::begin(@0x123233) }
    fun people(): (address, address, address) { (@0x124323, @0xE05, @0xFACE) }

    #[test]
    #[expected_failure(abort_code = E_TOO_MUCH_RELAYER_FEE)] // E_TOO_MUCH_RELAYER_FEE
    fun test_transfer_native_token_too_much_relayer_fee(){
        let (admin, _, _) = people();
        let test = scenario();
        // Set up core and token bridges.
        test = set_up_wormhole_core_and_token_bridges(admin, test);
        // Initialize the coin.
        native_coin_10_decimals::test_init(ctx(&mut test));
        // Register native asset type with the token bridge, mint some coins,
        // and initiate transfer.
        next_tx(&mut test, admin);{
            let bridge_state = take_shared<State>(&test);
            let worm_state = take_shared<WormholeState>(&test);
            let coin_meta = take_shared<CoinMetadata<NATIVE_COIN_10_DECIMALS>>(&test);
            let treasury_cap = take_shared<TreasuryCap<NATIVE_COIN_10_DECIMALS>>(&test);
            state::register_native_asset_test_only(
                &mut bridge_state,
                &coin_meta,
            );
            let coins = coin::mint<NATIVE_COIN_10_DECIMALS>(&mut treasury_cap, 10000, ctx(&mut test));

            transfer_tokens<NATIVE_COIN_10_DECIMALS>(
                &mut bridge_state,
                &mut worm_state,
                coins,
                coin::zero<SUI>(ctx(&mut test)), // zero fee paid to wormhole
                3, // recipient chain id
                external_address::from_any_bytes(x"deadbeef0000beef"), // recipient address
                100000000, // relayer fee (too much)
                0 // nonce is unused field for now
            );
            return_shared<State>(bridge_state);
            return_shared<WormholeState>(worm_state);
            return_shared<CoinMetadata<NATIVE_COIN_10_DECIMALS>>(coin_meta);
            return_shared<TreasuryCap<NATIVE_COIN_10_DECIMALS>>(treasury_cap);
        };
        test_scenario::end(test);
    }

    #[test]
    fun test_transfer_native_token(){
        let (admin, _, _) = people();
        let test = scenario();
        // Set up core and token bridges.
        test = set_up_wormhole_core_and_token_bridges(admin, test);
        // Initialize the coin.
        native_coin_10_decimals::test_init(ctx(&mut test));
        // Register native asset type with the token bridge, mint some coins,
        // and finally initiate transfer.
        next_tx(&mut test, admin);{
            let bridge_state = take_shared<State>(&test);
            let worm_state = take_shared<WormholeState>(&test);
            let coin_meta = take_shared<CoinMetadata<NATIVE_COIN_10_DECIMALS>>(&test);
            let treasury_cap = take_shared<TreasuryCap<NATIVE_COIN_10_DECIMALS>>(&test);
            state::register_native_asset_test_only(
                &mut bridge_state,
                &coin_meta,
            );
            let coins = coin::mint<NATIVE_COIN_10_DECIMALS>(&mut treasury_cap, 10000, ctx(&mut test));

            transfer_tokens<NATIVE_COIN_10_DECIMALS>(
                &mut bridge_state,
                &mut worm_state,
                coins,
                coin::zero<SUI>(ctx(&mut test)), // zero fee paid to wormhole
                3, // recipient chain id
                external_address::from_bytes(x"000000000000000000000000000000000000000000000000deadbeef0000beef"), // recipient address
                0, // relayer fee
                0 // unused field for now
            );
            return_shared<State>(bridge_state);
            return_shared<WormholeState>(worm_state);
            return_shared<CoinMetadata<NATIVE_COIN_10_DECIMALS>>(coin_meta);
            return_shared<TreasuryCap<NATIVE_COIN_10_DECIMALS>>(treasury_cap);
        };
        let tx_effects = next_tx(&mut test, admin);
        // A single user event should be emitted, corresponding to
        // publishing a Wormhole message for the token transfer
        assert!(num_user_events(&tx_effects)==1, 0);

        // check that custody of the coins is indeed transferred to token bridge
        next_tx(&mut test, admin);{
            let bridge_state = take_shared<State>(&test);
            let cur_bal = state::custody_balance<NATIVE_COIN_10_DECIMALS>(&mut bridge_state);
            assert!(cur_bal==10000, 0);
            return_shared<State>(bridge_state);
        };
        test_scenario::end(test);
    }

    #[test]
    fun test_transfer_wrapped_token(){
        let (admin, _, _) = people();
        let test = scenario();
        // Set up core and token bridges.
        test = set_up_wormhole_core_and_token_bridges(admin, test);
        // Initialize the wrapped coin and register the eth chain.
        wrapped_coin_12_decimals::test_init(ctx(&mut test));
        // Register chain emitter (chain id x emitter address) that attested
        // the wrapped token.
        next_tx(&mut test, admin);{
            let bridge_state = take_shared<State>(&test);
            state::register_new_emitter_test_only(
                &mut bridge_state,
                2, // chain ID
                external_address::from_bytes(
                    x"00000000000000000000000000000000000000000000000000000000deadbeef"
                )
            );
            return_shared<State>(bridge_state);
        };
        // Register wrapped asset type with the token bridge, mint some coins,
        // and finally initiate transfer.
        next_tx(&mut test, admin);{
            let bridge_state = take_shared<State>(&test);
            let worm_state = take_shared<WormholeState>(&test);
            let coin_meta = take_shared<CoinMetadata<WRAPPED_COIN_12_DECIMALS>>(&test);
            let new_wrapped_coin =
                take_from_address<Unregistered<WRAPPED_COIN_12_DECIMALS>>(&test, admin);

            // register wrapped asset with the token bridge
            create_wrapped::register_new_coin<WRAPPED_COIN_12_DECIMALS>(
                &mut bridge_state,
                &mut worm_state,
                new_wrapped_coin,
                &mut coin_meta,
                ctx(&mut test)
            );

            let coins =
                state::put_into_circulation_test_only<WRAPPED_COIN_12_DECIMALS>(
                    &mut bridge_state,
                    1000, // amount
                    ctx(&mut test)
                );

            transfer_tokens<WRAPPED_COIN_12_DECIMALS>(
                &mut bridge_state,
                &mut worm_state,
                coins,
                coin::zero<SUI>(ctx(&mut test)), // zero fee paid to wormhole
                3, // recipient chain id
                external_address::from_bytes(x"000000000000000000000000000000000000000000000000deadbeef0000beef"), // recipient address
                0, // relayer fee
                0 // unused field for now
            );
            return_shared<State>(bridge_state);
            return_shared<WormholeState>(worm_state);
            return_shared<CoinMetadata<WRAPPED_COIN_12_DECIMALS>>(coin_meta);
        };
        let tx_effects = next_tx(&mut test, admin);
        // A single user event should be emitted, corresponding to
        // publishing a Wormhole message for the token transfer
        assert!(num_user_events(&tx_effects)==1, 0);
        // How to check if token was actually burned?
        test_scenario::end(test);
    }

}
