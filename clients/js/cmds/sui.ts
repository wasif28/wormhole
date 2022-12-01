import yargs from "yargs";
import { callEntryFunc } from "../sui";
import { spawnSync } from 'child_process';


type Network = "MAINNET" | "TESTNET" | "DEVNET"


exports.command = 'aptos';
exports.desc = 'Aptos utilities ';
exports.builder = function(y: typeof yargs) {
  return y
    .command("init-token-bridge", "Init token bridge contract", (yargs) => {
      return yargs
        .option("network", network_options)
        .option("rpc", rpc_description)
        // TODO(csongor): once the sdk has this, just use it from there
        .option("contract-address", {
          alias: "a",
          required: true,
          describe: "Address where the wormhole module is deployed",
          type: "string",
        })
    }, async (argv) => {
      const network = argv.network.toUpperCase();
      assertNetwork(network);
      const contract_address = evm_address(argv["contract-address"]);
      const rpc = argv.rpc ?? NETWORKS[network]["aptos"].rpc;
      await callEntryFunc(network, rpc, `${contract_address}::token_bridge`, "init", [], []);
    })