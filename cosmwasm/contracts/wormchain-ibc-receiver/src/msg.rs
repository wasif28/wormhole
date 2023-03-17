use cosmwasm_schema::{cw_serde, QueryResponses};
use cosmwasm_std::{Response, Binary};

#[cw_serde]
pub enum ExecuteMsg {
    /// Submit one or more signed VAAs to update the on-chain state.  If processing any of the VAAs
    /// returns an error, the entire transaction is aborted and none of the VAAs are committed.
    SubmitUpdateChainConnection {
        /// One or more VAAs to be submitted.  Each VAA should be encoded in the standard wormhole
        /// wire format.
        vaas: Vec<Binary>
    }
}

/// This is the message we send over the IBC channel
#[cw_serde]
pub enum WormholeIbcPacketMsg {
    Publish { msg: Response }
}

/// Contract queries
#[cw_serde]
#[derive(QueryResponses)]
pub enum QueryMsg {
    #[returns(ChainConnectionResponse)]
    ChainConnection(u16),
}

#[cw_serde]
pub struct ChainConnectionResponse {
    pub connection_id: Binary,
}