import { Ed25519Keypair, JsonRpcProvider, RawSigner} from '@mysten/sui.js';
import { NETWORKS } from "./networks";
import { execSync } from "child_process";


type Network = "MAINNET" | "TESTNET" | "DEVNET"

function loadSigner(
    network: Network,
    rpc: string | undefined,
){
    let private_key_str_base_64: string | undefined = NETWORKS[network]["sui"].key;
    if (private_key_str_base_64 === undefined) {
      throw new Error("No key for Sui");
    }
    let priv_key_bytes = new Uint8Array(Buffer.from(private_key_str_base_64, 'base64'))
    let keypair = Ed25519Keypair.fromSeed(priv_key_bytes.slice(33))
    if (typeof rpc != 'undefined') {
        rpc = NETWORKS[network]["sui"].rpc
    }
    let provider = new JsonRpcProvider(rpc);
    const signer = new RawSigner(keypair, provider);
    return signer
}

// Reference: https://github.com/MystenLabs/sui/tree/main/sdk/typescript
// TODO - why does publish result in error?
export async function publishPackage(
    network: Network,
    rpc: string | undefined,
    packagePath: string,
){
    console.log("publish package network: ", network)
    console.log("publish package rpc: ", rpc)

    let signer = loadSigner(network, rpc)
    const compiledModules: string[] = JSON.parse(
        execSync(
          `docker run -it -v ${packagePath}:${packagePath} -w ${packagePath} ghcr.io/wormhole-foundation/sui:0.17.0a sui move build --dump-bytecode-as-base64 --path ${packagePath} | tail -1`,
          { encoding: 'utf-8' }
        )
      );
      console.log("compiled modules: ", compiledModules)
      const publishTxn = await signer.publish({
        compiledModules: compiledModules,
        gasBudget: 10000,
      });
      console.log('publishTxn', publishTxn);
}

export async function callEntryFunc(
    network: Network,
    rpc: string | undefined,
    packageObjectId: string,
    module: string,
    func: string,
    type_args: Array<string>,
    args: Array<string>,
) {
    let signer = loadSigner(network, rpc);
    const moveCallTxn = await signer.executeMoveCall({
        packageObjectId: packageObjectId,
        module: module,
        function: func,
        typeArguments: type_args,
        arguments: args,
        gasBudget: 20000,
      });
      console.log('moveCallTxn', moveCallTxn);
}
