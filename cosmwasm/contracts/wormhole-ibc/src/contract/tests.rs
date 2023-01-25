// instantiate
// 1. success - happy path
// 2. failure - mock wormhole core bridge function to fail

// handle_submit_wormchain_receiver_update_vaa
// 1. failure - parsing vaa fails (mock core contract function to fail)
// 2. failure - invalid chain
// 3. failure - invalid emitter address
// 4. failure - parsing governance packet
// 5. failure - invalid governance chain (can we generate tests for all chains aside from the chain::any?)
// 6. failure - not a Action::RegisterChain governance action
// 7. failure - chain we are registering is not wormchain
// 8. failure - parsing wormchain_ibc_receiver_addr fails
// 9. failure - saving wormchain_ibc_receiver_addr in storage? Need to mock to make this work
// 10. success - validate the correct response with the event and attributes is returned

// post_message_ibc
// 1. failure - mock the querier to fail
// 2. failure - mock getting the wormchain_receiver_addr to fail
// 3. failure - mock getting matching channel id to fail
// 4. failure - mock core contract execution to fail
// 5. success - validate IBC packet was sent? How to do this?

// find_wormchain_channel_id
// 1. failure - no matching channel found
// 2. success - matching channel found (happy path)