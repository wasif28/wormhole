use cosmwasm_schema::cw_serde;
use cosmwasm_std::{Response, Binary};
use wormhole::msg::ExecuteMsg as CoreExecuteMsg;

#[cw_serde]
pub enum ExecuteMsg {
    /// Submit one or more signed VAAs to update the on-chain state.  If processing any of the VAAs
    /// returns an error, the entire transaction is aborted and none of the VAAs are committed.
    SubmitUpdateWormchainReceiverVAA {
        /// One or more VAAs to be submitted.  Each VAA should be encoded in the standard wormhole
        /// wire format.
        vaa: Binary,
    },
    CoreExecuteMsg(CoreExecuteMsg),
}

/// This is the message we send over the IBC channel
#[cw_serde]
pub enum WormholeIbcPacketMsg {
    Publish { msg: Response }
}