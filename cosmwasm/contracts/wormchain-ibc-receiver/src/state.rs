use cw_storage_plus::Map;
use cosmwasm_std::Binary;

pub const CHAIN_CONNECTIONS: Map<u16, Binary> = Map::new("chain_connections");