# IBC Bridging

## Objective

Wormchain is a cosmos-sdk based chain that is IBC-enabled. We can leverage IBC generic messaging to reduce the operational burden required to run a guardian node. Wormhole guardians should, therefore, be capable of scaling to support all cosmos chains at minimal cost while only running a full node for wormchain.

## Background

[IBC](https://ibcprotocol.org/) is the canonical method of generic message passing within the cosmos ecosystem. All cosmos chains have IBC functionality built-in, and can enable it to connect with other cosmos chains.

[Wormchain](https://github.com/wormhole-foundation/wormhole/tree/main/wormchain) is a cosmos-sdk based blockchain that has been purpose-built to support the wormhole network. It allows the guardians to store state on all the blockchains which wormhole connects to, and enables a suite of product and security features.

## Goals

- Remove the requirement for guardians to run full nodes for cosmos chains. Guardians should be able to support all Cosmos chains which have IBC enabled by only running a full wormchain node.
- Define a custom IBC specification for passing wormhole messages between cosmos chains and wormchain.
- Ensure the design is backwards-compatible with existing cosmos integrations.

## Non-Goals

This document is not meant to put forward a timeline or plan of the cosmos networks that wormhole will support in the future. It is focused on the technical design of how we will use IBC generic messaging to reduce the operational load on wormhole guardians.

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
- During instantiation, it saves additional state: the `wormchain-ibc-receiver` cosmwasm contract address. This state is later used to properly choose the IBC channel over which to send the IBC message.
- During execution, it delegates all logic to the core bridge library. After the core bridge library has finished execution, it will send the response as an IBC message to the `wormchain-ibc-receiver` contract <b>if and only if</b> the execution message is of type `wormhole::msg::ExecuteMsg::PostMessage`.

The `wormchain-ibc-receiver` contract will be deployed on wormchain and is meant to receive the IBC messages that the `wormhole-ibc` contract sends from various cosmos chains. Its only responsibility is to receive the IBC message, send an IBC acknowledgement to the sender chain, and then emit the message for the guardian node to observe.

### IBC Relayers

All IBC communication is facilitated by [IBC relayers](https://ibcprotocol.org/relayers/). Since these are lightweight processes that need to only listen to blockchain RPC nodes, each (only several is also acceptable) wormhole guardian can run a relayer.

The guardian IBC relayers are be configured to connect the `wormchain-ibc-receiver` contract on wormchain to the various `wormhole-ibc` contracts on the cosmos chains that wormhole supports.

### Guardian Node Watcher

We will modify the cosmos guardian watcher to watch the `wormchain-ibc-receiver` contract on wormchain for the messages from the designated `wormhole-ibc` contracts on supported cosmos chains. This is nearly identical to the current model and can be a drop in replacement.

### API / database schema

```rust
/// This is the message we send over the IBC channel
#[cw_serde]
pub enum WormholeIbcPacketMsg {
    Publish { msg: Response }
}
```

## Caveats

### Lack of broad cosmwasm support

Some cosmos blockchains do not support cosmwasm smart contracting and have no plans to do so. For these chains, we will likely have to choose one of the following options:
1. Implement the wormhole contract stack as a native cosmos-sdk module in go.
2. Use the alternative design (detailed below in the [alternatives](#alternatives-considered) section)


## Alternatives Considered

### Routing Token Transfers through Wormchain

For chains that do not support cosmwasm smart contracting, we can use an alternative design that is only dependent on the native cosmos-sdk ibc-transfer module.

Under this design, we would enable the ibc-transfer module on wormchain and deploy the wormhole cosmwasm contract stack to wormchain along with an `wormhole-ibc-integrator` contract which cross calls to the token bridge contract. Going in/out of the cosmos ecosystem would then work as follows:
- External Chain -> Cosmos Chain
    - Token Bridge Payload 3 transfer to wormchain, designated to the `wormhole-ibc-integrator` contract where the extra payload designates the recipient cosmos chain and address on that chain.
    - The `wormhole-ibc-integrator` contract will internally call the TokenBridge contract on wormchain to verify the VAA, and then will decode the payload to mint the tokens and perform an IBC transfer to the target cosmos chain and address.
- Cosmos Chain -> External Chain
    - IBC transfer to the `wormhole-ibc-integrator` contract where the `FungibleTokenPacketData` metadata contains the Wormhole chain ID and bytes32 address. Upon receipt the `wormhole-ibc-integrator` contract will cross call the wormchain TokenBridge contract to transfer the tokens with the designated destination (if destination is WormChain, it could just transfer them directly instead).
    - If a dApp/user messes up the metadata (providing invalid chain ID, for example), we can reject this transfer and avoid stuck funds.
    - To avoid the complexity of multi-hop IBC assets, we can disable transfers for tokens that have already been bridged through IBC to other chains. To make this easy for users, we can compose on top of the [IBC Packet Forwarding Middleware](https://github.com/strangelove-ventures/packet-forward-middleware) so that we fully unwrap the token first.

Note that this design does not support generic IBC messages. To use custom IBC messages for chains that do not support cosmwasm, we'd be better off implementing the wormhole contract stack as a native cosmos-sdk go module.

## Security Considerations

<i>

This is the place to mention how your design approaches security: what surfaces does it exposed to (un)trusted users, what (un)trusted data it processes, what privileges will it run with in production.

</i>
