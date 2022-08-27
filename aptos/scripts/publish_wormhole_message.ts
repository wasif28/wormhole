import { AptosAccount, TxnBuilderTypes, BCS, HexString, MaybeHexString, AptosClient, FaucetClient, AptosAccountObject } from "aptos";
import {aptosAccountObject} from "./constants";
export const NODE_URL = "http://0.0.0.0:8080/v1";
export const FAUCET_URL = "http://0.0.0.0:8081";

const client = new AptosClient(NODE_URL);

async function publishWormholeMessage(contractAddress: HexString, accountFrom: AptosAccount): Promise<string> {
    const scriptFunctionPayload = new TxnBuilderTypes.TransactionPayloadEntryFunction(
      TxnBuilderTypes.EntryFunction.natural(
        `${contractAddress.toString()}::state`,
        "publish_message",
        [],
        [
         BCS.bcsSerializeUint64(1), // nonce
         BCS.bcsSerializeBytes(Buffer.from("hi my name is bob")), // payload
         BCS.bcsSerializeU8(5), //consistency level
        ]
      ),
    );
    const [{ sequence_number: sequenceNumber }, chainId] = await Promise.all([
      client.getAccount(accountFrom.address()),
      client.getChainId(),
    ]);
    const rawTxn = new TxnBuilderTypes.RawTransaction(
      TxnBuilderTypes.AccountAddress.fromHex(accountFrom.address()),
      BigInt(sequenceNumber),
      scriptFunctionPayload,
      BigInt(1000), //max gas to be used
      BigInt(1), //price per unit gas
      BigInt(Math.floor(Date.now() / 1000) + 10),
      new TxnBuilderTypes.ChainId(chainId),
    );

    const bcsTxn = AptosClient.generateBCSTransaction(accountFrom, rawTxn);
    const transactionRes = await client.submitSignedBCSTransaction(bcsTxn);

    return transactionRes.hash;
  }

  async function main(){
    let accountFrom = AptosAccount.fromAptosAccountObject(aptosAccountObject)
    let accountAddress = accountFrom.address();//new HexString("277fa055b6a73c42c0662d5236c65c864ccbf2d4abd21f174a30c8b786eab84b");
    console.log("account address: ", accountAddress);
    let hash = await publishWormholeMessage(accountAddress, accountFrom);
    console.log("tx hash: ", hash);
  }

  if (require.main === module) {
    main().then((resp) => console.log(resp));
  }


