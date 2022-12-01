import { textToHexString } from '@certusone/wormhole-sdk';
import { Ed25519Keypair, JsonRpcProvider, RawSigner } from '@mysten/sui.js';
import { NETWORKS } from "./networks";

//let private_key = new Uint8Array(Buffer.from("AGEL2sY5slGBrnl7Fyob6YN3kiTjzzrakHDZIGcg66VNjkJIyXxMqwdReEZrCrJpgbyQUSMkGID/0RRCcOB+JtE=", 'base64'))
let private_key_str = new Uint8Array(Buffer.from("AGEL2sY5slGBrnl7Fyob6YN3kiTjzzrakHDZIGcg66VNjkJIyXxMqwdReEZrCrJpgbyQUSMkGID/0RRCcOB+JtE=", 'base64'))
let pub_key = Ed25519Keypair.fromSeed(private_key_str.slice(33)).getPublicKey()
console.log("pub key: ", pub_key)
//let private_key = Buffer.from(Ed25519Keypair.fromSeed(private_key_str.slice(32)).getPublicKey()).toString('base64'))
//private_key = private_key.slice(1) //first byte is 00, indicating that it is ed25519
//console.log(Ed25519Keypair.fromSecretKey(private_key))

export async function callEntryFunc(
    network: "MAINNET" | "TESTNET" | "DEVNET",
    rpc: string | undefined,
    packageObjectId: string,
    module: string,
    func: string,
    type_args: Array<string>,
    args: Array<string>,
) {
    let private_key_str_base_64: string | undefined = NETWORKS[network]["sui"].key;
    if (private_key_str_base_64 === undefined) {
      throw new Error("No key for Sui");
    }
    let priv_key_bytes = new Uint8Array(Buffer.from("private_key_str", 'base64'))
    let keypair = Ed25519Keypair.fromSeed(priv_key_bytes.slice(33))
    if (typeof rpc != 'undefined') {
        rpc = NETWORKS[network]["sui"].rpc
    }
    let provider = new JsonRpcProvider(rpc);
    const signer = new RawSigner(keypair, provider);
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

//     const accountFrom = new AptosAccount(new Uint8Array(Buffer.from(key, "hex")));
//     let client: AptosClient;
//     // if rpc arg is passed in, then override default rpc value for that network

//     if (typeof rpc != 'undefined') {
//       client = new AptosClient(rpc);
//     } else {
//       client = new AptosClient(NETWORKS[network]["aptos"].rpc);
//     }
//     const [{ sequence_number: sequenceNumber }, chainId] = await Promise.all([
//       client.getAccount(accountFrom.address()),
//       client.getChainId(),
//     ]);
