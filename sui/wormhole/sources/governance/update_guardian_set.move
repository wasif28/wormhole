module wormhole::update_guardian_set {
    use std::vector::{Self};
    use sui::tx_context::{TxContext};

    use wormhole::bytes::{Self};
    use wormhole::cursor::{Self};
    use wormhole::guardian::{Self, Guardian};
    use wormhole::guardian_set::{Self};
    use wormhole::state::{Self, State};
    use wormhole::vaa::{Self};

    const E_WRONG_GUARDIAN_LEN: u64 = 0x0;
    const E_NO_GUARDIAN_SET: u64 = 0x1;
    const E_INVALID_MODULE: u64 = 0x2;
    const E_INVALID_ACTION: u64 = 0x3;
    const E_INVALID_TARGET: u64 = 0x4;
    const E_NON_INCREMENTAL_GUARDIAN_SETS: u64 = 0x5;

    struct UpdateGuardianSet {
        new_index: u32,
        guardians: vector<Guardian>,
    }

    public entry fun submit_vaa(
        state: &mut State,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let vaa = vaa::parse_and_verify(state, vaa, ctx);
        vaa::assert_governance(state, &vaa);
        vaa::replay_protect(state, &vaa);

        do_upgrade(state, parse_payload(vaa::destroy(vaa)), ctx)
    }

    fun do_upgrade(
        state: &mut State,
        upgrade: UpdateGuardianSet,
        ctx: &TxContext
    ) {
        let current_index = state::guardian_set_index(state);

        let UpdateGuardianSet {
            new_index,
            guardians,
        } = upgrade;

        assert!(
            new_index == current_index + 1,
            E_NON_INCREMENTAL_GUARDIAN_SETS
        );

        state::expire_guardian_set(state, ctx);

        state::update_guardian_set_index(state, new_index);
        state::store_guardian_set(
            state,
            guardian_set::new(new_index, guardians)
        );
    }

    #[test_only]
    public fun do_upgrade_test(
        s: &mut State,
        new_index: u32,
        guardians: vector<Guardian>,
        ctx: &mut TxContext
    ) {
        do_upgrade(s, UpdateGuardianSet { new_index, guardians }, ctx)
    }

    public fun parse_payload(bytes: vector<u8>): UpdateGuardianSet {
        let cur = cursor::new(bytes);
        let guardians = vector::empty<Guardian>();

        let target_module = bytes::to_bytes(&mut cur, 32);
        let expected_module =
            x"00000000000000000000000000000000000000000000000000000000436f7265"; // Core
        assert!(target_module == expected_module, E_INVALID_MODULE);

        let action = bytes::deserialize_u8(&mut cur);
        assert!(action == 0x02, E_INVALID_ACTION);

        let chain = bytes::deserialize_u16_be(&mut cur);
        assert!(chain == 0, E_INVALID_TARGET);

        let new_index = bytes::deserialize_u32_be(&mut cur);
        let guardian_len = bytes::deserialize_u8(&mut cur);

        while (guardian_len > 0) {
            let key = bytes::to_bytes(&mut cur, 20);
            vector::push_back(&mut guardians, guardian::new(key));
            guardian_len = guardian_len - 1;
        };

        cursor::destroy_empty(cur);

        UpdateGuardianSet {
            new_index,
            guardians
        }
    }

    #[test_only]
    public fun split(upgrade: UpdateGuardianSet): (u32, vector<Guardian>) {
        let UpdateGuardianSet { new_index, guardians } = upgrade;
        (new_index, guardians)
    }
}

#[test_only]
module wormhole::guardian_set_upgrade_test {
    use std::vector;
    use sui::test_scenario::{Self};

    use wormhole::cursor::{Self};
    use wormhole::guardian::{Self};
    use wormhole::guardian_set::{Self};
    use wormhole::state::{Self, State};
    use wormhole::update_guardian_set::{Self};
    use wormhole::wormhole_scenario::{set_up_wormhole};


    fun people(): (address, address, address) { (@0x124323, @0xE05, @0xFACE) }

    #[test]
    public fun test_parse_guardian_set_upgrade() {
        let b =
            x"00000000000000000000000000000000000000000000000000000000436f7265020000000000011358cc3ae5c097b213ce3c81979e1b9f9570746aa5ff6cb952589bde862c25ef4392132fb9d4a42157114de8460193bdf3a2fcf81f86a09765f4762fd1107a0086b32d7a0977926a205131d8731d39cbeb8c82b2fd82faed2711d59af0f2499d16e726f6b211b39756c042441be6d8650b69b54ebe715e234354ce5b4d348fb74b958e8966e2ec3dbd4958a7cdeb5f7389fa26941519f0863349c223b73a6ddee774a3bf913953d695260d88bc1aa25a4eee363ef0000ac0076727b35fbea2dac28fee5ccb0fea768eaf45ced136b9d9e24903464ae889f5c8a723fc14f93124b7c738843cbb89e864c862c38cddcccf95d2cc37a4dc036a8d232b48f62cdd4731412f4890da798f6896a3331f64b48c12d1d57fd9cbe7081171aa1be1d36cafe3867910f99c09e347899c19c38192b6e7387ccd768277c17dab1b7a5027c0b3cf178e21ad2e77ae06711549cfbb1f9c7a9d8096e85e1487f35515d02a92753504a8d75471b9f49edb6fbebc898f403e4773e95feb15e80c9a99c8348d";
        let (new_index, guardians) =
            update_guardian_set::split(update_guardian_set::parse_payload(b));
        let guardians = cursor::new(guardians);
        assert!(new_index == 1, 0);
        assert!(vector::length(cursor::data(&guardians)) == 19, 0);
        let expected = cursor::new(vector[
            guardian::new(x"58cc3ae5c097b213ce3c81979e1b9f9570746aa5"),
            guardian::new(x"ff6cb952589bde862c25ef4392132fb9d4a42157"),
            guardian::new(x"114de8460193bdf3a2fcf81f86a09765f4762fd1"),
            guardian::new(x"107a0086b32d7a0977926a205131d8731d39cbeb"),
            guardian::new(x"8c82b2fd82faed2711d59af0f2499d16e726f6b2"),
            guardian::new(x"11b39756c042441be6d8650b69b54ebe715e2343"),
            guardian::new(x"54ce5b4d348fb74b958e8966e2ec3dbd4958a7cd"),
            guardian::new(x"eb5f7389fa26941519f0863349c223b73a6ddee7"),
            guardian::new(x"74a3bf913953d695260d88bc1aa25a4eee363ef0"),
            guardian::new(x"000ac0076727b35fbea2dac28fee5ccb0fea768e"),
            guardian::new(x"af45ced136b9d9e24903464ae889f5c8a723fc14"),
            guardian::new(x"f93124b7c738843cbb89e864c862c38cddcccf95"),
            guardian::new(x"d2cc37a4dc036a8d232b48f62cdd4731412f4890"),
            guardian::new(x"da798f6896a3331f64b48c12d1d57fd9cbe70811"),
            guardian::new(x"71aa1be1d36cafe3867910f99c09e347899c19c3"),
            guardian::new(x"8192b6e7387ccd768277c17dab1b7a5027c0b3cf"),
            guardian::new(x"178e21ad2e77ae06711549cfbb1f9c7a9d8096e8"),
            guardian::new(x"5e1487f35515d02a92753504a8d75471b9f49edb"),
            guardian::new(x"6fbebc898f403e4773e95feb15e80c9a99c8348d"),
        ]);
        while (!cursor::is_empty(&guardians) && !cursor::is_empty(&expected)) {
            let left = guardian::to_bytes(cursor::poke(&mut guardians));
            let right = guardian::to_bytes(cursor::poke(&mut expected));
            assert!(left == right, 0);
        };
        cursor::destroy_empty(guardians);
        cursor::destroy_empty(expected);
    }

    #[test]
    public fun test_guardian_set_expiry() {
        let (admin, caller, _) = people();
        let my_scenario = test_scenario::begin(admin);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        test_scenario::next_tx(scenario, caller);

        {
            let worm_state = test_scenario::take_shared<State>(scenario);
            let first_index = state::guardian_set_index(&worm_state);
            let set = state::guardian_set_at(&worm_state, &first_index);
            // make sure guardian set is active
            assert!(
                guardian_set::is_active(set, test_scenario::ctx(scenario)),
                0
            );

            // do an upgrade
            update_guardian_set::do_upgrade_test(
                &mut worm_state,
                1, // guardian set index
                vector[
                    guardian::new(x"71aa1be1d36cafe3867910f99c09e347899c19c3")
                ], // new guardian set
                test_scenario::ctx(scenario),
            );

            // make sure old guardian set is still active
            let set = state::guardian_set_at(&worm_state, &first_index);
            assert!(
                guardian_set::is_active(set, test_scenario::ctx(scenario)),
                0
            );

            // Fast forward time beyond expiration by 3 epochs
            test_scenario::next_epoch(scenario, caller);
            test_scenario::next_epoch(scenario, caller);
            test_scenario::next_epoch(scenario, caller);

            // make sure old guardian set is no longer active
            assert!(
                !guardian_set::is_active(set, test_scenario::ctx(scenario)),
                0
            );

            test_scenario::return_shared<State>(worm_state);
        };

        // Done.
        test_scenario::end(my_scenario);
    }

}