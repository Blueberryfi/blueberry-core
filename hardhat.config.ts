import "@typechain/hardhat";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "solidity-coverage";
import "hardhat-abi-exporter";
// import 'hardhat-gas-reporter';
import "hardhat-contract-sizer";
import "@openzeppelin/hardhat-upgrades";
import { HardhatUserConfig } from "hardhat/config";
import dotenv from "dotenv";

dotenv.config();

let deployAccountKey: string;
if (!process.env.DEPLOY_ACCOUNT_KEY) {
  throw new Error("Please set your DEPLOY_ACCOUNT_KEY in a .env file");
} else {
  deployAccountKey = process.env.DEPLOY_ACCOUNT_KEY;
}

/** let alchemyapi: string;
* if (!process.env.ALCHEMY_API_KEY) {
*  throw new Error("Please set your ALCHEMY_API_KEY in a .env file");
* } else {
*   alchemyapi = process.env.ALCHEMY_API_KEY;
* }
*
* let infuraApiKey: string;
* if (!process.env.INFURA_API_KEY) {
*  throw new Error("Please set your INFURA_API_KEY in a .env file");
* } else {
*   infuraApiKey = process.env.INFURA_API_KEY;
* }
*
*/

/** let llamaApiKey: string;
* if (!process.env.LLAMA_API_KEY) {
*   throw new Error("Please set your LLAMA_API_KEY in a .env file");
* } else {
*   llamaApiKey = process.env.LLAMA_API_KEY;
* }
*/

// let devnetUrl: string;
// if (!process.env.DEVNET_URL) {
//   throw new Error("Please set your DEVNET_URL in a .env file");
// } else {
//   devnetUrl = process.env.DEVNET_URL;
// }

const config: HardhatUserConfig = {
  typechain: {
    target: "ethers-v5",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      forking: {
        url: `https://rpc.ankr.com/eth`,
        blockNumber: 17089048,
      },
    },
/**     mainnet: {
      accounts: [deployAccountKey],
      chainId: 1,
      url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyapi}`,
    },
    goerli: {
      accounts: [deployAccountKey],
      url: `https://eth-goerli.alchemyapi.io/v2/${alchemyapi}`,
    },
*/    
  },
  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    flat: true,
    spacing: 2,
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: false,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  mocha: {
    timeout: 100000000,
  },
};

export default config;
