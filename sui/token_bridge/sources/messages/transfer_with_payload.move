module token_bridge::transfer_with_payload {
    use std::vector::{Self};
    use wormhole::bytes::{Self};
    use wormhole::cursor::{Self};
    use wormhole::emitter::{Self, EmitterCap};
    use wormhole::external_address::{Self, ExternalAddress};

    use token_bridge::normalized_amount::{Self, NormalizedAmount};

    const E_INVALID_ACTION: u64 = 0;

    const PAYLOAD_ID: u8 = 3;

    struct TransferWithPayload has drop {
        // Amount being transferred (big-endian uint256).
        amount: NormalizedAmount,
        // Address of the token. Left-zero-padded if shorter than 32 bytes.
        token_address: ExternalAddress,
        // Chain ID of the token.
        token_chain: u16,
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes.
        recipient: ExternalAddress,
        // Chain ID of the recipient.
        recipient_chain: u16,
        // Address of the message sender. Left-zero-padded if shorter than 32 bytes.
        sender: ExternalAddress,
        // An arbitrary payload.
        payload: vector<u8>,
    }

    public fun payload_id(): u8 {
        PAYLOAD_ID
    }

    public fun new_from_emitter(
        emitter_cap: &EmitterCap,
        amount: NormalizedAmount,
        token_address: ExternalAddress,
        token_chain: u16,
        recipient: ExternalAddress,
        recipient_chain: u16,
        payload: vector<u8>
    ): TransferWithPayload {
        new(
            amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            emitter::addr(emitter_cap),
            payload
        )
    }

    public fun unpack(
        transfer: TransferWithPayload
    ): (
        NormalizedAmount,
        ExternalAddress,
        u16,
        ExternalAddress,
        u16,
        ExternalAddress,
        vector<u8>
    ) {
        let TransferWithPayload {
            amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            sender,
            payload
        } = transfer;

        (
            amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            sender,
            payload
        )
    }

    public fun amount(self: &TransferWithPayload): NormalizedAmount {
        self.amount
    }

    public fun token_address(self: &TransferWithPayload): ExternalAddress {
        self.token_address
    }

    public fun token_chain(self: &TransferWithPayload): u16 {
        self.token_chain
    }

    public fun recipient(self: &TransferWithPayload): ExternalAddress {
        self.recipient
    }

    public fun recipient_chain(self: &TransferWithPayload): u16 {
        self.recipient_chain
    }

    public fun sender(self: &TransferWithPayload): ExternalAddress {
        self.sender
    }

    public fun payload(self: &TransferWithPayload): vector<u8> {
        self.payload
    }

    public fun deserialize(transfer: vector<u8>): TransferWithPayload {
        let cur = cursor::new(transfer);
        assert!(bytes::take_u8(&mut cur) == PAYLOAD_ID, E_INVALID_ACTION);

        let amount = normalized_amount::take_bytes(&mut cur);
        let token_address = external_address::take_bytes(&mut cur);
        let token_chain = bytes::take_u16_be(&mut cur);
        let recipient = external_address::take_bytes(&mut cur);
        let recipient_chain = bytes::take_u16_be(&mut cur);
        let sender = external_address::take_bytes(&mut cur);

        new(
            amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            sender,
            cursor::take_rest(cur)
        )
    }

    public fun serialize(transfer: TransferWithPayload): vector<u8> {
        let (
            amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            sender,
            payload
        ) = unpack(transfer);

        let buf = vector::empty<u8>();
        bytes::push_u8(&mut buf, PAYLOAD_ID);
        bytes::push_u256_be(&mut buf, normalized_amount::to_u256(amount));
        vector::append(&mut buf, external_address::to_bytes(token_address));
        bytes::push_u16_be(&mut buf, token_chain);
        vector::append(&mut buf, external_address::to_bytes(recipient));
        bytes::push_u16_be(&mut buf, recipient_chain);
        vector::append(&mut buf, external_address::to_bytes(sender));
        vector::append(&mut buf, payload);

        buf
    }

    fun new(
        amount: NormalizedAmount,
        token_address: ExternalAddress,
        token_chain: u16,
        recipient: ExternalAddress,
        recipient_chain: u16,
        sender: ExternalAddress,
        payload: vector<u8>
    ): TransferWithPayload {
        TransferWithPayload {
            amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            sender,
            payload
        }
    }

    #[test_only]
    public fun destroy(transfer: TransferWithPayload) {
        unpack(transfer);
    }
}

#[test_only]
module token_bridge::transfer_with_payload_tests {
    use std::vector::{Self};
    use wormhole::emitter::{Self};
    use wormhole::external_address::{Self};

    use token_bridge::dummy_message::{Self};
    use token_bridge::normalized_amount::{Self};
    use token_bridge::transfer_with_payload::{Self};

    #[test]
    fun test_serialize() {
        let emitter_cap =
            emitter::dummy_cap(external_address::from_any_bytes(x"deadbeef"));
        let amount = normalized_amount::from_raw(234567890, 8);
        let token_address = external_address::from_any_bytes(x"beef");
        let token_chain = 1;
        let recipient = external_address::from_any_bytes(x"cafe");
        let recipient_chain = 7;
        let payload = b"All your base are belong to us.";

        let new_transfer =
            transfer_with_payload::new_from_emitter(
                &emitter_cap,
                amount,
                token_address,
                token_chain,
                recipient,
                recipient_chain,
                payload
            );

        // Verify getters.
        assert!(
            transfer_with_payload::amount(&new_transfer) == amount,
            0
        );
        assert!(
            transfer_with_payload::token_address(&new_transfer) == token_address,
            0
        );
        assert!(
            transfer_with_payload::token_chain(&new_transfer) == token_chain,
            0
        );
        assert!(
            transfer_with_payload::recipient(&new_transfer) == recipient,
            0
        );
        assert!(
            transfer_with_payload::recipient_chain(&new_transfer) == recipient_chain,
            0
        );
        assert!(
            transfer_with_payload::sender(&new_transfer) == emitter::addr(&emitter_cap),
            0
        );
        assert!(
            transfer_with_payload::payload(&new_transfer) == payload,
            0
        );

        let serialized = transfer_with_payload::serialize(new_transfer);
        let expected_serialized =
            dummy_message::encoded_transfer_with_payload();
        assert!(serialized == expected_serialized, 0);

        // Clean up.
        emitter::destroy_cap(emitter_cap);
    }

    #[test]
    public fun test_deserialize() {
        let expected_amount = normalized_amount::from_raw(234567890, 8);
        let expected_token_address = external_address::from_any_bytes(x"beef");
        let expected_token_chain = 1;
        let expected_recipient = external_address::from_any_bytes(x"cafe");
        let expected_recipient_chain = 7;
        let expected_sender = external_address::from_any_bytes(x"deadbeef");
        let expected_payload = b"All your base are belong to us.";

        let parsed =
            transfer_with_payload::deserialize(
                dummy_message::encoded_transfer_with_payload()
            );

        // Verify getters.
        assert!(
            transfer_with_payload::amount(&parsed) == expected_amount,
            0
        );
        assert!(
            transfer_with_payload::token_address(&parsed) == expected_token_address,
            0
        );
        assert!(
            transfer_with_payload::token_chain(&parsed) == expected_token_chain,
            0
        );
        assert!(
            transfer_with_payload::recipient(&parsed) == expected_recipient,
            0
        );
        assert!(
            transfer_with_payload::recipient_chain(&parsed) == expected_recipient_chain,
            0
        );
        assert!(
            transfer_with_payload::sender(&parsed) == expected_sender,
            0
        );
        assert!(
            transfer_with_payload::payload(&parsed) == expected_payload,
            0
        );

        let (
            amount,
            token_address,
            token_chain,
            recipient,
            recipient_chain,
            sender,
            payload
        ) = transfer_with_payload::unpack(parsed);
        assert!(amount == expected_amount, 0);
        assert!(token_address == expected_token_address, 0);
        assert!(token_chain == expected_token_chain, 0);
        assert!(recipient == expected_recipient, 0);
        assert!(recipient_chain == expected_recipient_chain, 0);
        assert!(sender == expected_sender, 0);
        assert!(payload == expected_payload, 0);
    }

    #[test]
    #[expected_failure(abort_code = transfer_with_payload::E_INVALID_ACTION)]
    public fun test_cannot_deserialize_invalid_payload() {
        let invalid_payload = token_bridge::dummy_message::encoded_transfer();

        // Show that the first byte is not the expected payload ID.
        assert!(
            *vector::borrow(&invalid_payload, 0) != transfer_with_payload::payload_id(),
            0
        );

        // You shall not pass!
        let parsed = transfer_with_payload::deserialize(invalid_payload);

        // Clean up.
        transfer_with_payload::destroy(parsed);
    }
}
