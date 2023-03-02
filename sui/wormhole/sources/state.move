module wormhole::state {
    use std::vector::{Self};
    use sui::coin::{Coin};
    use sui::dynamic_field::{Self as field};
    use sui::object::{Self, UID};
    use sui::sui::{SUI};
    use sui::table::{Self, Table};
    use sui::tx_context::{TxContext};

    use wormhole::bytes32::{Self, Bytes32};
    use wormhole::cursor::{Self};
    use wormhole::emitter::{Self, EmitterCap, EmitterRegistry};
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::fee_collector::{Self, FeeCollector};
    use wormhole::guardian::{Self};
    use wormhole::guardian_set::{Self, GuardianSet};
    use wormhole::set::{Self, Set};
    use wormhole::upgrade_tracker::{Self, UpgradeTracker};

    // NOTE: This exists to mock up sui::package for proposed ugprades.
    use wormhole::dummy_sui_package::{
        Self as package,
        UpgradeCap,
        UpgradeReceipt,
        UpgradeTicket
    };

    friend wormhole::migrate;
    friend wormhole::publish_message;
    friend wormhole::set_fee;
    friend wormhole::setup;
    friend wormhole::transfer_fee;
    friend wormhole::update_guardian_set;
    friend wormhole::upgrade_contract;
    friend wormhole::vaa;

    const E_INVALID_UPGRADE_CAP_VERSION: u64 = 0;
    const E_ZERO_GUARDIANS: u64 = 1;
    const E_VAA_ALREADY_CONSUMED: u64 = 2;
    const E_IMPLEMENTATION_VERSION_MISMATCH: u64 = 3;

    /// Sui's chain ID is hard-coded to one value.
    const CHAIN_ID: u16 = 21;

    /// This value tracks the current version of the Wormhole version.
    const DECLARED_IMPLEMENTATION_VERSION: u64 = 1;

    const KEY_MIGRATION_CONTROL: vector<u8> = b"migration_control";

    const KEY_VERSION_NEW_EMITTER: vector<u8> = b"new_emitter";
    const KEY_VERSION_PARSE_AND_VERIFY: vector<u8> = b"parse_and_verify";
    const KEY_VERSION_PUBLISH_MESSAGE: vector<u8> = b"publish_message";
    const KEY_VERSION_SET_FEE: vector<u8> = b"set_fee";
    const KEY_VERSION_TRANSFER_FEE: vector<u8> = b"transfer_fee";
    const KEY_VERSION_UPDATE_GUARDIAN_SET: vector<u8> = b"update_guardian_set";

    struct State has key, store {
        id: UID,

        /// Governance chain ID.
        governance_chain: u16,

        /// Governance contract address.
        governance_contract: ExternalAddress,

        /// Current active guardian set index.
        guardian_set_index: u32,

        /// All guardian sets (including expired ones).
        guardian_sets: Table<u32, GuardianSet>,

        /// Period for which a guardian set stays active after it has been
        /// replaced.
        ///
        /// Currently in terms of Sui epochs until we have access to a clock
        /// with unix timestamp.
        guardian_set_epochs_to_live: u32,

        /// Consumed VAA hashes to protect against replay. VAAs relevant to
        /// Wormhole are just governance VAAs.
        consumed_vaa_hashes: Set<Bytes32>,

        /// Registry for new emitter caps (`EmitterCap`).
        emitter_registry: EmitterRegistry,

        /// Wormhole fee collector.
        fee_collector: FeeCollector,

        upgrade_cap: UpgradeCap,

        /// Contract upgrade tracker.
        upgrade_tracker: UpgradeTracker
    }

    public(friend) fun new(
        upgrade_cap: UpgradeCap,
        governance_chain: u16,
        governance_contract: vector<u8>,
        initial_guardians: vector<vector<u8>>,
        guardian_set_epochs_to_live: u32,
        message_fee: u64,
        ctx: &mut TxContext
    ): State {
        assert!(
            package::version(&upgrade_cap) == DECLARED_IMPLEMENTATION_VERSION,
            E_INVALID_UPGRADE_CAP_VERSION
        );
        assert!(vector::length(&initial_guardians) > 0, E_ZERO_GUARDIANS);

        // First guardian set index is zero. New guardian sets must increment
        // from the last recorded index.
        let guardian_set_index = 0;

        let governance_contract =
            external_address::from_nonzero_bytes(
                governance_contract
            );
        let state = State {
            id: object::new(ctx),
            governance_chain,
            governance_contract,
            guardian_set_index,
            guardian_sets: table::new(ctx),
            guardian_set_epochs_to_live,
            consumed_vaa_hashes: set::new(ctx),
            emitter_registry: emitter::new_registry(),
            fee_collector: fee_collector::new(message_fee),
            upgrade_cap,
            upgrade_tracker: upgrade_tracker::new(
                DECLARED_IMPLEMENTATION_VERSION,
                ctx
            )
        };

        let guardians = {
            let out = vector::empty();
            let cur = cursor::new(initial_guardians);
            while (!cursor::is_empty(&cur)) {
                vector::push_back(
                    &mut out,
                    guardian::new(cursor::poke(&mut cur))
                );
            };
            cursor::destroy_empty(cur);
            out
        };

        // Store the initial guardian set.
        store_guardian_set(
            &mut state,
            guardian_set::new(guardian_set_index, guardians)
        );

        // Add dynamic field to control whether someone can call `migrate`. Set
        // this value to `false` by default.
        //
        // See `migrate` module for more info.
        field::add(&mut state.id, KEY_MIGRATION_CONTROL, false);

        let tracker = &mut state.upgrade_tracker;
        upgrade_tracker::add(tracker, KEY_VERSION_NEW_EMITTER);
        upgrade_tracker::add(tracker, KEY_VERSION_PARSE_AND_VERIFY);
        upgrade_tracker::add(tracker, KEY_VERSION_PUBLISH_MESSAGE);
        upgrade_tracker::add(tracker, KEY_VERSION_SET_FEE);
        upgrade_tracker::add(tracker, KEY_VERSION_TRANSFER_FEE);
        upgrade_tracker::add(tracker, KEY_VERSION_UPDATE_GUARDIAN_SET);

        state
    }

    public fun chain_id(): u16 {
        CHAIN_ID
    }

    public fun version(): u64 {
         DECLARED_IMPLEMENTATION_VERSION
    }

    public fun governance_module(): Bytes32 {
        // A.K.A. "Core".
        bytes32::new(
            x"00000000000000000000000000000000000000000000000000000000436f7265"
        )
    }

    /// Issue an `UpgradeTicket` for the upgrade.
    public(friend) fun authorize_upgrade(
        self: &mut State,
        implementation_digest: Bytes32
    ): UpgradeTicket {
        let policy = package::upgrade_policy(&self.upgrade_cap);
        package::authorize_upgrade(
            &mut self.upgrade_cap,
            policy,
            bytes32::to_bytes(implementation_digest),
        )
    }

    /// Finalize the upgrade that ran to produce the given `receipt`.
    public(friend) fun commit_upgrade(
        self: &mut State,
        receipt: UpgradeReceipt
    ) {
        // Uptick the upgrade cap version number using this receipt.
        package::commit_upgrade(&mut self.upgrade_cap, receipt);

        // Check that the hard-coded version version agrees with the
        // upticked version number.
        assert!(
            package::version(&self.upgrade_cap) == DECLARED_IMPLEMENTATION_VERSION,
            E_IMPLEMENTATION_VERSION_MISMATCH
        );

        // Update global version.
        upgrade_tracker::update_global(
            &mut self.upgrade_tracker,
            DECLARED_IMPLEMENTATION_VERSION
        );

        // Enable `migrate` to be called after commiting the upgrade.
        //
        // A separate method is required because `state` is a dependency of
        // `migrate`. This method warehouses state modifications required
        // for the new implementation plus enabling any methods required to be
        // gated by the current implementation version. In most cases `migrate`
        // is a no-op. But it still must be called in order to reset the
        // migration control to `false`.
        //
        // See `migrate` module for more info.
       enable_migration(self);
    }

    public(friend) fun require_current_version_for(
        self: &mut State,
        control_key: vector<u8>
    ) {
        upgrade_tracker::require_current_version(
            &mut self.upgrade_tracker,
            control_key
        )
    }

    public fun can_migrate(self: &State): bool {
        *field::borrow(&self.id, KEY_MIGRATION_CONTROL)
    }

    public(friend) fun enable_migration(self: &mut State) {
        *field::borrow_mut(&mut self.id, KEY_MIGRATION_CONTROL) = true;
    }

    public(friend) fun disable_migration(self: &mut State) {
        *field::borrow_mut(&mut self.id, KEY_MIGRATION_CONTROL) = false;
    }

    public fun assert_new_emitter_control(self: &State) {
        assert_control(self, KEY_VERSION_NEW_EMITTER)
    }

    public fun assert_parse_and_verify_control(self: &State) {
        assert_control(self, KEY_VERSION_PARSE_AND_VERIFY)
    }

    public fun assert_publish_message_control(self: &State) {
        assert_control(self, KEY_VERSION_PUBLISH_MESSAGE)
    }

    public fun assert_set_fee_control(self: &State) {
        assert_control(self, KEY_VERSION_SET_FEE)
    }

    public fun assert_transfer_fee_control(self: &State) {
        assert_control(self, KEY_VERSION_TRANSFER_FEE)
    }

    public fun assert_update_guardian_set_control(self: &State) {
        assert_control(self, KEY_VERSION_UPDATE_GUARDIAN_SET)
    }

    public fun governance_chain(self: &State): u16 {
        self.governance_chain
    }

    public fun governance_contract(self: &State): ExternalAddress {
        self.governance_contract
    }

    public fun guardian_set_index(self: &State): u32 {
        self.guardian_set_index
    }

    public fun guardian_set_epochs_to_live(self: &State): u32 {
        self.guardian_set_epochs_to_live
    }

    public fun message_fee(self: &State): u64 {
        return fee_collector::fee_amount(&self.fee_collector)
    }

    public fun deposit_fee(self: &mut State, coin: Coin<SUI>) {
        fee_collector::deposit(&mut self.fee_collector, coin);
    }

    public(friend) fun withdraw_fee(
        self: &mut State,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<SUI> {
        fee_collector::withdraw(&mut self.fee_collector, amount, ctx)
    }

    public fun fees_collected(self: &State): u64 {
        fee_collector::balance_value(&self.fee_collector)
    }

    public(friend) fun consume_vaa_hash(self: &mut State, vaa_hash: Bytes32) {
        let consumed = &mut self.consumed_vaa_hashes;
        assert!(!set::contains(consumed, vaa_hash), E_VAA_ALREADY_CONSUMED);
        set::add(consumed, vaa_hash);
    }

    public(friend) fun expire_guardian_set(self: &mut State, ctx: &TxContext) {
        let expiring =
            table::borrow_mut(&mut self.guardian_sets, self.guardian_set_index);
        guardian_set::set_expiration(
            expiring,
            self.guardian_set_epochs_to_live,
            ctx
        );
    }

    public(friend) fun store_guardian_set(
        self: &mut State,
        new_guardian_set: GuardianSet
    ) {
        self.guardian_set_index = guardian_set::index(&new_guardian_set);
        table::add(
            &mut self.guardian_sets,
            self.guardian_set_index,
            new_guardian_set
        );
    }

    public(friend) fun set_message_fee(self: &mut State, amount: u64) {
        fee_collector::change_fee(&mut self.fee_collector, amount);
    }

    public fun guardian_set_at(self: &State, index: u32): &GuardianSet {
        table::borrow(&self.guardian_sets, index)
    }

    public fun is_guardian_set_active(
        self: &State,
        set: &GuardianSet,
        ctx: &TxContext
    ): bool {
        (
            self.guardian_set_index == guardian_set::index(set) ||
            guardian_set::is_active(set, ctx)
        )
    }

    public fun new_emitter(
        self: &mut State,
        ctx: &mut TxContext
    ): EmitterCap{
        assert_new_emitter_control(self);

        emitter::new_cap(&mut self.emitter_registry, ctx)
    }

    public(friend) fun use_emitter_sequence(
        emitter_cap: &mut EmitterCap
    ): u64 {
        emitter::use_sequence(emitter_cap)
    }

    fun assert_control(self: &State, key: vector<u8>) {
        upgrade_tracker::assert_current(
            &self.upgrade_tracker,
            key,
            DECLARED_IMPLEMENTATION_VERSION
        )
    }
}
