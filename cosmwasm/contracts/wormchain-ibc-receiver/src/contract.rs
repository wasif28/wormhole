use anyhow::Context;
use cosmwasm_std::{entry_point, Empty, StdError};
use cosmwasm_std::{DepsMut, Env, MessageInfo, Response};
use cw2::{set_contract_version, get_contract_version};
use semver::Version;

// version info for migration info
const CONTRACT_NAME: &str = "crates.io:wormchain-ibc-receiver";
const CONTRACT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn instantiate(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    _msg: Empty,
) -> Result<Response, anyhow::Error> {
    set_contract_version(deps.storage, CONTRACT_NAME, CONTRACT_VERSION)
        .context("failed to set contract version")?;

    Ok(Response::new()
        .add_attribute("action", "instantiate")
        .add_attribute("owner", info.sender)
        .add_attribute("version", CONTRACT_VERSION))
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty) -> Result<Response, anyhow::Error> {
    let ver = get_contract_version(deps.storage)?;
    // ensure we are migrating from an allowed contract
    if ver.contract != CONTRACT_NAME {
        return Err(StdError::generic_err("Can only upgrade from same type").into());
    }

    // ensure we are migrating to a newer version
    let saved_version = Version::parse(&ver.version)
        .context("could not parse saved contract version")?;
    let new_version = Version::parse(CONTRACT_VERSION)
        .context("could not parse new contract version")?;
    if saved_version >= new_version {
        return Err(StdError::generic_err("Cannot upgrade from a newer or equal version").into());
    }

    // set the new version
    cw2::set_contract_version(deps.storage, CONTRACT_NAME, CONTRACT_VERSION)?;

    Ok(Response::default())
}

#[cfg(test)]
mod tests {
    use cosmwasm_std::{testing::{
        mock_dependencies, mock_info, mock_env
    }, Empty};
    use cw2::get_contract_version;
    
    use super::{instantiate, CONTRACT_NAME, CONTRACT_VERSION};
    
    #[test]
    fn instantiate_works() {
        let mut deps = mock_dependencies();
    
        const SENDER: &str = "creator";
        let info = mock_info(SENDER, &[]);
        let res = instantiate(deps.as_mut(), mock_env(), info, Empty {}).unwrap();
    
        // the response should have 0 messages and 3 attributes
        assert_eq!(0, res.messages.len());
        assert_eq!(3, res.attributes.len());

        // validate the attributes and their values
        res.attributes.iter().for_each(|a| {
            let value = if a.key == "action" {
                "instantiate"
            } else if a.key == "owner" {
                SENDER
            } else if a.key == "version" {
                CONTRACT_VERSION
            } else {
                panic!("invalid attribute key");
            };

            assert_eq!(a.value, value);
        });
    
        // check that contract version & name have been set
        let contract_version = get_contract_version(deps.as_ref().storage).unwrap();
        assert_eq!(CONTRACT_NAME, contract_version.contract);
        assert_eq!(CONTRACT_VERSION, contract_version.version);
    }
}