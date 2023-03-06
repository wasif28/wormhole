module wormhole::governance_message {
    use sui::tx_context::{TxContext};
    use wormhole::bytes::{Self};
    use wormhole::bytes32::{Self, Bytes32};
    use wormhole::cursor::{Self};
    use wormhole::state::{Self, State, chain_id};
    use wormhole::vaa::{Self, VAA};

    const E_OLD_GUARDIAN_SET_GOVERNANCE: u64 = 0;
    const E_INVALID_GOVERNANCE_CHAIN: u64 = 1;
    const E_INVALID_GOVERNANCE_EMITTER: u64 = 2;
    const E_INVALID_GOVERNANCE_MODULE: u64 = 4;
    const E_INVALID_GOVERNANCE_ACTION: u64 = 5;
    const E_GOVERNANCE_TARGET_CHAIN_NONZERO: u64 = 6;
    const E_GOVERNANCE_TARGET_CHAIN_NOT_SUI: u64 = 7;

    struct GovernanceMessage {
        module_name: Bytes32,
        action: u8,
        chain: u16,
        payload: vector<u8>,
        vaa_hash: Bytes32
    }

    public fun module_name(self: &GovernanceMessage): Bytes32 {
        self.module_name
    }

    public fun action(self: &GovernanceMessage): u8 {
        self.action
    }

    public fun is_global_action(self: &GovernanceMessage): bool {
        self.chain == 0
    }

    public fun is_local_action(self: &GovernanceMessage): bool {
        self.chain == chain_id()
    }

    public fun vaa_hash(self: &GovernanceMessage): Bytes32 {
        self.vaa_hash
    }

    #[test_only]
    public fun payload(self: &GovernanceMessage): vector<u8> {
        self.payload
    }

    public fun take_payload(msg: GovernanceMessage): vector<u8> {
        let GovernanceMessage {
            module_name: _,
            action: _,
            chain: _,
            vaa_hash: _,
            payload
        } = msg;

        payload
    }

    public fun parse_and_verify_vaa(
        wormhole_state: &mut State,
        vaa_buf: vector<u8>,
        ctx: &TxContext
    ): GovernanceMessage {
        let parsed =
            vaa::parse_and_verify(
                wormhole_state,
                vaa_buf,
                ctx
            );

        // This VAA must have originated from the governance emitter.
        assert_governance_emitter(wormhole_state, &parsed);

        let vaa_hash = vaa::hash(&parsed);

        let cur = cursor::new(vaa::take_payload(parsed));

        let module_name = bytes32::take(&mut cur);
        let action = bytes::take_u8(&mut cur);
        let chain = bytes::take_u16_be(&mut cur);
        let payload = cursor::rest(cur);

        GovernanceMessage { module_name, action, chain, payload, vaa_hash }
    }

    public fun take_global_action(
        msg: GovernanceMessage,
        expected_module_name: Bytes32,
        expected_action: u8
    ): vector<u8> {
        assert_module_and_action(&msg, expected_module_name, expected_action);

        // New guardian sets are applied to all Wormhole contracts.
        assert!(is_global_action(&msg), E_GOVERNANCE_TARGET_CHAIN_NONZERO);

        take_payload(msg)
    }

    public fun take_local_action(
        msg: GovernanceMessage,
        expected_module_name: Bytes32,
        expected_action: u8
    ): vector<u8> {
        assert_module_and_action(&msg, expected_module_name, expected_action);

        // New guardian sets are applied to all Wormhole contracts.
        assert!(is_local_action(&msg), E_GOVERNANCE_TARGET_CHAIN_NOT_SUI);

        take_payload(msg)
    }

    fun assert_module_and_action(
        self: &GovernanceMessage,
        expected_module_name: Bytes32,
        expected_action: u8
    ) {
        // Governance action must be for Wormhole (Core Bridge).
        assert!(
            self.module_name == expected_module_name,
            E_INVALID_GOVERNANCE_MODULE
        );

        // Action must be specifically to update the guardian set.
        assert!(
            self.action == expected_action,
            E_INVALID_GOVERNANCE_ACTION
        );
    }

    #[test_only]
    public fun assert_module_and_action_test_only(
        self: &GovernanceMessage,
        expected_module_name: Bytes32,
        expected_action: u8
    ) {
        assert_module_and_action(self, expected_module_name, expected_action)
    }

    /// Aborts if the VAA is not governance (i.e. sent from the governance
    /// emitter on the governance chain)
    fun assert_governance_emitter(wormhole_state: &State, parsed: &VAA) {
        // Protect against governance actions enacted using an old guardian set.
        // This is not a protection found in the other Wormhole contracts.
        assert!(
            vaa::guardian_set_index(parsed) == state::guardian_set_index(wormhole_state),
            E_OLD_GUARDIAN_SET_GOVERNANCE
        );

        // Both the emitter chain and address must equal those known by the
        // Wormhole `State`.
        assert!(
            vaa::emitter_chain(parsed) == state::governance_chain(wormhole_state),
            E_INVALID_GOVERNANCE_CHAIN
        );
        assert!(
            vaa::emitter_address(parsed) == state::governance_contract(wormhole_state),
            E_INVALID_GOVERNANCE_EMITTER
        );
    }

    #[test_only]
    public fun assert_governance_emitter_test_only(
        wormhole_state: &State,
        parsed: &VAA
    ) {
        assert_governance_emitter(wormhole_state, parsed)
    }

    #[test_only]
    public fun destroy(msg: GovernanceMessage) {
        take_payload(msg);
    }
}

#[test_only]
module wormhole::governance_message_test {
    use sui::test_scenario::{Self};

    use wormhole::bytes32::{Self};
    use wormhole::state::{Self, State};
    use wormhole::governance_message::{Self};
    use wormhole::wormhole_scenario::{set_up_wormhole, person};

    const VAA_UPDATE_GUARDIAN_SET_1: vector<u8> =
        x"010000000001004f74e9596bd8246ef456918594ae16e81365b52c0cf4490b2a029fb101b058311f4a5592baeac014dc58215faad36453467a85a4c3e1c6cf5166e80f6e4dc50b0100bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000010100000000000000000000000000000000000000000000000000000000436f72650200000000000113befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe88d7d8b32a9105d228100e72dffe2fae0705d31c58076f561cc62a47087b567c86f986426dfcd000bd6e9833490f8fa87c733a183cd076a6cbd29074b853fcf0a5c78c1b56d15fce7a154e6ebe9ed7a2af3503dbd2e37518ab04d7ce78b630f98b15b78a785632dea5609064803b1c8ea8bb2c77a6004bd109a281a698c0f5ba31f158585b41f4f33659e54d3178443ab76a60e21690dbfb17f7f59f09ae3ea1647ec26ae49b14060660504f4da1c2059e1c5ab6810ac3d8e1258bd2f004a94ca0cd4c68fc1c061180610e96d645b12f47ae5cf4546b18538739e90f2edb0d8530e31a218e72b9480202acbaeb06178da78858e5e5c4705cdd4b668ffe3be5bae4867c9d5efe3a05efc62d60e1d19faeb56a80223cdd3472d791b7d32c05abb1cc00b6381fa0c4928f0c56fc14bc029b8809069093d712a3fd4dfab31963597e246ab29fc6ebedf2d392a51ab2dc5c59d0902a03132a84dfd920b35a3d0ba5f7a0635df298f9033e";
     const VAA_SET_FEE_1: vector<u8> =
        x"01000000000100181aa27fd44f3060fad0ae72895d42f97c45f7a5d34aa294102911370695e91e17ae82caa59f779edde2356d95cd46c2c381cdeba7a8165901a562374f212d750000bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000010100000000000000000000000000000000000000000000000000000000436f7265030015000000000000000000000000000000000000000000000000000000000000015e";

    #[test]
    public fun test_global_action() {
        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test setting sender to `caller`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_UPDATE_GUARDIAN_SET_1,
                test_scenario::ctx(scenario)
            );

        let expected_module = state::governance_module();
        let expected_action = 2;

        // Verify `GovernanceMessage` getters.
        assert!(governance_message::module_name(&msg) == expected_module, 0);
        assert!(governance_message::action(&msg) == expected_action, 0);
        assert!(governance_message::is_global_action(&msg), 0);
        assert!(!governance_message::is_local_action(&msg), 0);

        let expected_payload = governance_message::payload(&msg);

        // Take payload.
        let payload =
            governance_message::take_global_action(
                msg,
                expected_module,
                expected_action
            );
        assert!(payload == expected_payload, 0);

        // Clean up.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    public fun test_local_action() {
        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test setting sender to `caller`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_SET_FEE_1,
                test_scenario::ctx(scenario)
            );

        let expected_module = state::governance_module();
        let expected_action = 3;

        // Verify `GovernanceMessage` getters.
        assert!(governance_message::module_name(&msg) == expected_module, 0);
        assert!(governance_message::action(&msg) == expected_action, 0);
        assert!(governance_message::is_local_action(&msg), 0);
        assert!(!governance_message::is_global_action(&msg), 0);

        let expected_payload = governance_message::payload(&msg);

        // Take payload.
        let payload =
            governance_message::take_local_action(
                msg,
                expected_module,
                expected_action
            );
        assert!(payload == expected_payload, 0);

        // Clean up.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(
        abort_code = governance_message::E_INVALID_GOVERNANCE_MODULE
    )]
    public fun test_cannot_assert_module_and_action_invalid_module() {
        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test setting sender to `caller`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_SET_FEE_1,
                test_scenario::ctx(scenario)
            );

        let expected_module = bytes32::default(); // all zeros
        let expected_action = 3;

        // Action agrees, but `assert_module_and_action` should fail.
        assert!(governance_message::action(&msg) == expected_action, 0);

        // You shall not pass!
        governance_message::assert_module_and_action_test_only(
            &msg,
            expected_module,
            expected_action
        );

        // Clean up.
        governance_message::destroy(msg);
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(
        abort_code = governance_message::E_INVALID_GOVERNANCE_ACTION
    )]
    public fun test_cannot_assert_module_and_action_invalid_action() {
        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test setting sender to `caller`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_SET_FEE_1,
                test_scenario::ctx(scenario)
            );

        let expected_module = state::governance_module();
        let expected_action = 0;

        // Action agrees, but `assert_module_and_action` should fail.
        assert!(governance_message::module_name(&msg) == expected_module, 0);

        // You shall not pass!
        governance_message::assert_module_and_action_test_only(
            &msg,
            expected_module,
            expected_action
        );

        // Clean up.
        governance_message::destroy(msg);
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(
        abort_code = governance_message::E_GOVERNANCE_TARGET_CHAIN_NONZERO
    )]
    public fun test_cannot_take_global_action_with_local() {
        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test setting sender to `caller`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_SET_FEE_1,
                test_scenario::ctx(scenario)
            );

        let expected_module = state::governance_module();
        let expected_action = 3;

        // Verify this message is not a global action.
        assert!(!governance_message::is_global_action(&msg), 0);

        // You shall not pass!
        governance_message::take_global_action(
            msg,
            expected_module,
            expected_action
        );

        // Clean up.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(
        abort_code = governance_message::E_GOVERNANCE_TARGET_CHAIN_NOT_SUI
    )]
    public fun test_cannot_take_local_action_with_invalid_chain() {
        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test setting sender to `caller`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_UPDATE_GUARDIAN_SET_1,
                test_scenario::ctx(scenario)
            );

        let expected_module = state::governance_module();
        let expected_action = 2;

        // Verify this message is not for Sui.
        assert!(!governance_message::is_local_action(&msg), 0);

        // You shall not pass!
        governance_message::take_local_action(
            msg,
            expected_module,
            expected_action
        );

        // Clean up.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }
}