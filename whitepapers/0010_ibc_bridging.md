# IBC Bridging

## Objective

Since Wormchain is a cosmos-sdk based chain that is IBC-enabled, we can leverage IBC generic messaging to reduce the operational burden required to run a guardian node. Wormhole guardians should, therefore, be capable of scaling to support all cosmos chains at minimal cost while only running a full node for Wormchain.

## Background

[IBC](https://ibcprotocol.org/) is the canonical method of generic message passing within the cosmos ecosystem. IBC is part of the cosmos-sdk and Cosmos chains can enable it to connect with other cosmos chains.

[Wormchain](https://github.com/wormhole-foundation/wormhole/tree/main/wormchain) is a cosmos-sdk based blockchain that has been purpose-built to support Wormhole. It allows the guardians to store global state on all the blockchains which wormhole connects to, and enables a suite of product and security features.

## Goals

- Remove the requirement for guardians to run full nodes for cosmos chains. Guardians should be able to support all Cosmos chains which have IBC enabled by only running a full wormchain node.
- Define a custom IBC specification for passing wormhole messages between cosmos chains and wormchain.
- Ensure this design is backwards-compatible with existing cosmos integrations.
- Ensure this design does not violate any of Wormhole's existing security assumptions.

## Non-Goals

This document does not propose new cosmos networks for Wormhole to support. It is focused on the technical design of using IBC generic messaging to reduce the operational load on wormhole guardians.

This document is also not meant to describe how wormhole can be scaled beyond the cosmos ecosystem.

## Overview

Currently wormhole guardians run full nodes for every chain that wormhole is connected to. This is done for maximum security and decentralization. Since each guardians runs a full node for each chain, they are able to independently verify the authenticity of wormhole messages that are posted on different blockchains. However, running full nodes has its drawbacks. Specifically, adding new chains to wormhole has a high operational cost per chain, which makes it difficult to scale wormhole.

Luckily, we can leverage standards such as IBC to scale wormhole's support for the cosmos ecosystem. Since Cosmos IBC messages are trustlessly verified by tendermint light clients, we can pass wormhole messages from any cosmos chain over IBC to wormchain, which will then emit that message for the wormhole guardians to pick up. This way, the wormhole guardians only need to run a full node for wormchain to be able to verify the authenticity of messages on all other IBC-enabled cosmos chains.

## Detailed Design

### External Chain -> Cosmos Chain

This will work exactly the same way it works today. We will deploy our wormhole cosmwasm contract stack to every cosmos chain we want to support. Wormhole relayers will be able to post VAAs produced for any source chain directly to the cosmos destination chain.

### Cosmos Chain -> External Chain

Typically, the wormhole core bridge contract emits a message which the guardians then pick up from their full nodes.

For cosmos chains, we update the core bridge contract to instead send this message over IBC to wormchain. Then a wormchain contract receives the message to emit and actually emits it, which the guardians then pick up.

Specifically, we implement two new cosmwasm smart contracts: `wormhole-ibc` and `wormchain-ibc-receiver`.

The `wormhole-ibc` contract is meant to replace the `wormhole` core bridge contract on cosmos chains. It imports the `wormhole` contract as a library and delegates core functionality to it before and after running custom logic:
- During execution, it delegates all logic to the core bridge library. After the core bridge library has finished execution, it will send the response as an IBC message to the `wormchain-ibc-receiver` contract <b>if and only if</b> the execution message is of type `wormhole::msg::ExecuteMsg::PostMessage`.

Sending an IBC packet requires choosing an IBC channel to send over. IBC `(channel_id, port_id)` pairs are unique. All IBC-enabled cosmwasm contracts follow a standard `port_id` format: `wasm.<contract_address>`. Therefore, to choose a correct channel the `wormhole-ibc` contract will need to know the address of the `wormchain-ibc-receiver` contract - it will select any channel that is paired with the expected port. 

The `wormchain-ibc-receiver` contract will be deployed on wormchain and is meant to receive the IBC messages that the `wormhole-ibc` contract sends from various cosmos chains. Its only responsibility is to receive the IBC message, send an IBC acknowledgement to the source chain, and then emit the message for the guardian node to observe.

### IBC Relayers

All IBC communication is facilitated by [IBC relayers](https://ibcprotocol.org/relayers/). Since these are lightweight processes that need to only listen to blockchain RPC nodes, each (only several is also acceptable) wormhole guardian can run a relayer.

The guardian IBC relayers are configured to connect the `wormchain-ibc-receiver` contract on wormchain to the various `wormhole-ibc` contracts on the cosmos chains that wormhole supports.

### Guardian Node Watcher

We will modify the cosmos guardian watcher to watch the `wormchain-ibc-receiver` contract on wormchain for the messages from the designated `wormhole-ibc` contracts on supported cosmos chains. This is nearly identical to the current model and can be a drop in replacement.

The new guardian watcher can verify that messages originate from the chain they claim to originate from by checking the IBC connection ID. The `wormchain-ibc-receiver` contract logs the connection ID that the message was received over. Since IBC connections are unique and can never be updated or closed ([docs](https://github.com/cosmos/ibc/tree/main/spec/core/ics-003-connection-semantics#sub-protocols)), the guardians can associate connection IDs with specific chains.

### API / database schema

```rust
/// This is the message we send over the IBC channel
#[cw_serde]
pub enum WormholeIbcPacketMsg {
    Publish { msg: Response }
}
```

## Deployment

There are several steps required to deploy this feature. Listed in order:

1. Deploying the new contracts: `wormhole-ibc` contracts to Cosmos chains and the `wormhole-ibc-receiver` contract to Wormchain.
2. Upgrading existing `wormhole` contracts on Cosmos chains to use the new `wormhole-ibc` bytecode.
3. Establishing IBC connections between the `wormhole-ibc` contracts and the `wormhole-ibc-receiver` contract.
4. Upgrading the guardian software.

First, we need to deploy the `wormhole-ibc-receiver` contract on Wormchain. This will require 2 governance VAAs to deploy and instantiate the bytecode.

Once we know the `wormhole-ibc-receiver` contract address, we can hardcode this (or, using an environment variable during compilation) into the `wormhole-ibc` contracts. Recall that these need to know the address of the `wormhole-ibc-receiver` contract to look up the correct IBC channel over which to send messages.

Next, we should deploy the compiled `wormhole-ibc` contracts to Cosmos chains we already support (Terra2, XPLA, and Injective). We can migrate the existing `wormhole` contract to the new `wormhole-ibc` bytecode so that we don't need to redeploy and re-instantiate the Cosmos token bridge contracts with new core bridge contract addresses.

Next, we should use relayers to establish connections between the `wormhole-ibc` contracts and the `wormchain-ibc-receiver` contract on Wormchain. Establishing the connections first is necessary so that we can build mappings of `connectionId -> chainId` in the guardian node.

Finally, we'll be ready to upgrade the guardians to a new software version.
