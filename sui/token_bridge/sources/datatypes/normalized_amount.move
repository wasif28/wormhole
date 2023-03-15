// SPDX-License-Identifier: Apache 2

/// This module implements a container that stores the token transfer amount
/// encoded in a Token Bridge message. These amounts are capped at 8 decimals.
/// This means that any amount of a coin whose metadata defines its decimals
/// as some value greater than 8, the encoded amount will be normalized to
/// eight decimals (which will lead to some residual amount after the transfer).
/// For inbound transfers, this amount will be denormalized (scaled by the same
/// decimal difference).
module token_bridge::normalized_amount {
    use sui::math::{Self};
    use wormhole::bytes::{Self};
    use wormhole::cursor::{Cursor};

    /// Container holding the value decoded from a Token Bridge transfer.
    struct NormalizedAmount has store, copy, drop {
        value: u64
    }

    public fun default(): NormalizedAmount {
        new(0)
    }

    public fun value(self: &NormalizedAmount): u64 {
        self.value
    }

    public fun to_u256(self: &NormalizedAmount): u256 {
        (self.value as u256)
    }

    public fun from_raw(amount: u64, decimals: u8): NormalizedAmount {
        if (amount == 0) {
            default()
        } else {
            let norm = {
                if (decimals > 8) {
                    amount / math::pow(10, decimals - 8)
                } else {
                    amount
                }
            };
            new(norm)
        }
    }

    public fun to_raw(norm: NormalizedAmount, decimals: u8): u64 {
        let NormalizedAmount { value } = norm;
         if (value > 0 && decimals > 8) {
            value * math::pow(10, decimals - 8)
         } else {
            value
         }
    }

    public fun take_bytes(cur: &mut Cursor<u8>): NormalizedAmount {
        // Amounts are encoded with 32 bytes.
        from_u256(bytes::take_u256_be(cur))
    }

    public fun push_u256_be(buf: &mut vector<u8>, norm: NormalizedAmount) {
        bytes::push_u256_be(buf, to_u256(&norm))
    }

    fun new(value: u64): NormalizedAmount {
        NormalizedAmount {
            value
        }
    }

    fun from_u256(value: u256): NormalizedAmount {
        assert!(value < (1u256 << 64), 0);
        new((value as u64))
    }
}

#[test_only]
module token_bridge::normalized_amount_test {
    use token_bridge::normalized_amount;

    #[test]
    fun test_normalize_denormalize_amount() {
        let a = 12345678910111;
        let b = normalized_amount::from_raw(a, 9);
        let c = normalized_amount::to_raw(b, 9);
        assert!(c == 12345678910110, 0);

        let x = 12345678910111;
        let y = normalized_amount::from_raw(x, 5);
        let z = normalized_amount::to_raw(y, 5);
        assert!(z == x, 0);
    }
}
