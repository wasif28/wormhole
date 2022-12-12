import { Ed25519Keypair, JsonRpcProvider, RawSigner} from '@mysten/sui.js';
import { NETWORKS } from "./networks";
import { execSync } from "child_process";
import { impossible, Payload } from "./vaa";

type Network = "MAINNET" | "TESTNET" | "DEVNET"

export async function execute_sui(
  payload: Payload,
  vaa: Buffer,
  network: "MAINNET" | "TESTNET" | "DEVNET",
  contract: string | undefined,
  rpc: string | undefined,
  packageObjectId: string | undefined
) {
  const chain = "sui";

  // turn VAA bytes into BCS format. That is, add a length prefix
  const serializer = new BCS.Serializer();
  serializer.serializeBytes(vaa);
  const bcsVAA = serializer.getBytes();

  switch (payload.module) {
    case "Core":
      contract = contract ?? CONTRACTS[network][chain]["core"];
      if (contract === undefined) {
        throw Error("core bridge contract is undefined")
      }
      switch (payload.type) {
        case "GuardianSetUpgrade":
          console.log("Submitting new guardian set")
          await callEntryFunc(network, rpc, packageObjectId, `${contract}::guardian_set_upgrade`, "submit_vaa_entry", [], [bcsVAA]);
          break
        case "ContractUpgrade":
          console.log("Upgrading core contract")
          await callEntryFunc(network, rpc, packageObjectId, `${contract}::contract_upgrade`, "submit_vaa_entry", [], [bcsVAA]);
          break
        default:
          impossible(payload)
      }
      break
    case "NFTBridge":
      contract = contract ?? CONTRACTS[network][chain]["nft_bridge"];
      if (contract === undefined) {
        throw Error("nft bridge contract is undefined")
      }
      break
    case "TokenBridge":
      contract = contract ?? CONTRACTS[network][chain]["token_bridge"];
      if (contract === undefined) {
        throw Error("token bridge contract is undefined")
      }
      switch (payload.type) {
        case "ContractUpgrade":
          console.log("Upgrading contract")
          await callEntryFunc(network, rpc, packageObjectId, `${contract}::contract_upgrade`, "submit_vaa_entry", [], [bcsVAA]);
          break
        case "RegisterChain":
          console.log("Registering chain")
          await callEntryFunc(network, rpc, packageObjectId, `${contract}::register_chain`, "submit_vaa_entry", [], [bcsVAA]);
          break
        case "AttestMeta": {
          console.log("Creating wrapped token")
          // Deploying a wrapped asset requires two transactions:
          // 1. Publish a new module under a resource account that defines a type T
          // 2. Initialise a new coin with that type T
          // These need to be done in separate transactions, becasue a
          // transaction that deploys a module cannot use that module
          //
          // Tx 1.
          try {
            await callEntryFunc(network, rpc, packageObjectId, `${contract}::wrapped`, "create_wrapped_coin_type", [], [bcsVAA]);
          } catch (e) {
            console.log("this one already happened (probably)")
          }

          // We just deployed the module (notice the "wait" argument which makes
          // the previous step block until finality).
          // Now we're ready to do Tx 2. The module above got deployed to a new
          // resource account, which is seeded by the token bridge's address and
          // the origin information of the token. We can recompute this address
          // offline:
          const tokenAddress = payload.tokenAddress;
          const tokenChain = payload.tokenChain;
          assertChain(tokenChain);
          let wrappedContract = deriveWrappedAssetAddress(hex(contract), tokenChain, hex(tokenAddress));

          // Tx 2.
          console.log(`Deploying resource account ${wrappedContract}`);
          let token = new TxnBuilderTypes.TypeTagStruct(TxnBuilderTypes.StructTag.fromString(`${wrappedContract}::coin::T`));
          await callEntryFunc(network, rpc, packageObjectId, `${contract}::wrapped`, "create_wrapped_coin", [token], [bcsVAA]);

          break
        }
        case "Transfer": {
          console.log("Completing transfer")
          // TODO: only handles wrapped assets for now
          const tokenAddress = payload.tokenAddress;
          const tokenChain = payload.tokenChain;
          assertChain(tokenChain);
          let wrappedContract = deriveWrappedAssetAddress(hex(contract), tokenChain, hex(tokenAddress));
          const token = new TxnBuilderTypes.TypeTagStruct(TxnBuilderTypes.StructTag.fromString(`${wrappedContract}::coin::T`));
          await callEntryFunc(network, rpc, packageObjectId, `${contract}::complete_transfer`, "submit_vaa_and_register_entry", [token], [bcsVAA]);
          break
        }
        case "TransferWithPayload":
          throw Error("Can't complete payload 3 transfer from CLI")
        default:
          impossible(payload)
          break
      }
      break
    default:
      impossible(payload)
  }
}

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
