#[cfg(not(feature = "library"))]
use cosmwasm_std::entry_point;

use anyhow::{ensure, Context};
use cosmwasm_std::{
    to_binary, DepsMut, Env, IbcChannel, IbcMsg, IbcQuery, ListChannelsResponse, MessageInfo,
    Response, StdError, StdResult, Binary, Event,
};
use cw2::{get_contract_version, set_contract_version};
use semver::Version;
use wormhole::contract::query_parse_and_verify_vaa;
use wormhole::msg::{ExecuteMsg as CoreExecuteMsg, MigrateMsg, InstantiateMsg};
use wormhole_sdk::Chain;
use wormhole_sdk::token::{GovernancePacket, Action};

use crate::bail;
use crate::error::ContractError;
use crate::ibc::PACKET_LIFETIME;
use crate::msg::{ExecuteMsg, WormholeIbcPacketMsg};
use crate::state::WORMCHAIN_IBC_RECEIVER_ADDR;

// version info for migration info
const CONTRACT_NAME: &str = "crates.io:wormhole-ibc";
const CONTRACT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn instantiate(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: InstantiateMsg,
) -> Result<Response, anyhow::Error> {
    // save the contract name and version
    set_contract_version(deps.storage, CONTRACT_NAME, CONTRACT_VERSION)
        .context("failed to set contract version")?;

    // execute the wormhole core contract instantiation
    wormhole::contract::instantiate(deps, env, info, msg)
        .context("wormhole core instantiation failed")
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn migrate(deps: DepsMut, env: Env, msg: MigrateMsg) -> Result<Response, anyhow::Error> {
    let ver = get_contract_version(deps.storage)?;
    // ensure we are migrating from an allowed contract
    if ver.contract != CONTRACT_NAME {
        return Err(StdError::generic_err("Can only upgrade from same type").into());
    }

    // ensure we are migrating to a newer version
    let saved_version =
        Version::parse(&ver.version).context("could not parse saved contract version")?;
    let new_version =
        Version::parse(CONTRACT_VERSION).context("could not parse new contract version")?;
    if saved_version >= new_version {
        return Err(StdError::generic_err("Cannot upgrade from a newer version").into());
    }

    // set the new version
    cw2::set_contract_version(deps.storage, CONTRACT_NAME, CONTRACT_VERSION)?;

    // call the core contract migrate function
    wormhole::contract::migrate(deps, env, msg).context("wormhole core migration failed")
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn execute(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: ExecuteMsg,
) -> Result<Response, anyhow::Error> {
    match msg {
        ExecuteMsg::SubmitUpdateWormchainReceiverVAA { vaa } => handle_submit_wormchain_receiver_update_vaa(deps, env, info, vaa),
        ExecuteMsg::CoreExecuteMsg(core_msg) => {
            match core_msg {
                CoreExecuteMsg::SubmitVAA { .. } => wormhole::contract::execute(deps, env, info, core_msg).context("failed core submit_vaa execution"),
                CoreExecuteMsg::PostMessage { .. } => post_message_ibc(deps, env, info, core_msg)
            }
        }
    }
}

fn post_message_ibc(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: CoreExecuteMsg,
) -> anyhow::Result<Response> {
    // search for a channel bound to counterparty with the port "wasm.<wormchain_addr>"
    let ibc_channels = deps
        .querier
        .query::<ListChannelsResponse>(&IbcQuery::ListChannels { port_id: None }.into())
        .context("failed to query ibc channels")?;

    let wormchain_ibc_receiver_addr = WORMCHAIN_IBC_RECEIVER_ADDR.load(deps.storage)
        .context("could not load wormchain_ibc_receiver_addr")?;
    let channel_id =
        find_wormchain_channel_id(ibc_channels.channels, wormchain_ibc_receiver_addr)?;

    // compute the packet timeout
    let packet_timeout = env.block.time.plus_seconds(PACKET_LIFETIME).into();

    // compute the block height
    let block_height = env.block.height.to_string();

    // compute the transaction index
    // (this is an optional since not all messages are executed as part of txns)
    // (they may be executed part of the pre/post block handlers)
    let tx_index = env.transaction.as_ref().map(|tx_info| tx_info.index);

    // actually execute the postMessage call on the core contract
    let res = wormhole::contract::execute(deps, env, info, msg)
        .context("wormhole core execution failed")?;

    let res_with_tx_index = match tx_index {
        Some(index) => res.add_attribute("message.tx_index", index.to_string()),
        None => res,
    };
    let res_with_block_height =
        res_with_tx_index.add_attribute("message.block_height", block_height);

    // Send the result attributes over IBC on this channel
    let packet = WormholeIbcPacketMsg::Publish {
        msg: res_with_block_height,
    };
    IbcMsg::SendPacket {
        channel_id,
        data: to_binary(&packet)?,
        timeout: packet_timeout,
    };

    Ok(Response::default())
}

/// Find any IBC channel that is connected to the wormchain integrator contract
fn find_wormchain_channel_id(
    channels: Vec<IbcChannel>,
    wormchain_addr: String,
) -> StdResult<String> {
    for c in channels {
        if c.counterparty_endpoint.port_id == format!("wasm.{wormchain_addr}") {
            return Ok(c.endpoint.channel_id);
        }
    }

    Err(StdError::not_found(format!(
        "no channel connecting to wormchain contract {wormchain_addr}"
    )))
}

fn handle_submit_wormchain_receiver_update_vaa(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    vaa: Binary
) -> anyhow::Result<Response> {
    // verify the VAA
    let vaa = query_parse_and_verify_vaa(deps.as_ref(), vaa.as_slice(), env.block.time.seconds())?;

    // ensure it's a governance VAA (from solana and the special governance emitter)
    if !(Chain::from(vaa.emitter_chain) == Chain::Solana
        && vaa.emitter_address == wormhole_sdk::GOVERNANCE_EMITTER.0)
    {
        // not allowed to submit anything other than governance VAA
        bail!(ContractError::InvalidVAAType);
    }

    // parse out the governance message from the VAA payload
    let govpacket: GovernancePacket = serde_wormhole::from_slice(&vaa.payload)
        .context("failed to parse governance packet")?;

    ensure!(
        govpacket.chain == Chain::Any,
        "this governance VAA is for another chain"
    );

    // ensure that this action is for registering an emitter from wormchain
    match govpacket.action {
        Action::RegisterChain {
            chain,
            emitter_address,
        } => {
            if chain != Chain::Wormchain {
                bail!(ContractError::InvalidChainRegistration);
            }
            let wormchain_ibc_receiver_addr = String::from_utf8(emitter_address.0.to_vec())
                .context("failed to parse chain registration address")?;

            WORMCHAIN_IBC_RECEIVER_ADDR
                .save(
                    deps.storage,
                    &wormchain_ibc_receiver_addr,
                )
                .context("failed to save chain registration")?;
            let event = Event::new("RegisterChain")
                .add_attribute("chain", chain.to_string())
                .add_attribute("emitter_address", emitter_address.to_string());
            
            Ok(Response::new()
                .add_attribute("action", "submit_wormchain_receiver_update_vaa")
                .add_attribute("owner", info.sender)
                .add_event(event))
        }
        _ => bail!("unsupported governance action"),
    }
}

#[cfg(test)]
mod tests;