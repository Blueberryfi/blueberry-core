import "@typechain/hardhat";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-dependency-compiler";
import "solidity-coverage";
import "hardhat-abi-exporter";
// import 'hardhat-gas-reporter';
import "hardhat-contract-sizer";
import "hardhat-deploy";
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

let alchemyapi: string;
if (!process.env.ALCHEMY_API_KEY) {
  throw new Error("Please set your ALCHEMY_API_KEY in a .env file");
} else {
  alchemyapi = process.env.ALCHEMY_API_KEY;
}

// let infuraApiKey: string;
// if (!process.env.INFURA_API_KEY) {
//   throw new Error("Please set your INFURA_API_KEY in a .env file");
// } else {
//   infuraApiKey = process.env.INFURA_API_KEY;
// }

/** let llamaApiKey: string;
 * if (!process.env.LLAMA_API_KEY) {
 *   throw new Error("Please set your LLAMA_API_KEY in a .env file");
 * } else {
 *   llamaApiKey = process.env.LLAMA_API_KEY;
 * }
 */

let buildbearApiKey = process.env.BUILDBEAR_API_KEY || "";

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
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
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
    buildbear: {
      accounts: [deployAccountKey],
      url: `https://rpc.buildbear.io/${buildbearApiKey}`,
      deploy: ["deploy/devnet"],
    },
    phalcon: {
      accounts: [deployAccountKey],
      url: process.env.PHALCON_RPC ?? "",
      chainId: 1,
      deploy: ["deploy/devnet"],
    },
    mainnet: {
      accounts: [deployAccountKey],
      chainId: 1,
      url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyapi}`,
      deploy: ["deploy/mainnet"],
    },
    /**
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
    except: ["IBaseOracle"]
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: false,
    strict: false,
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY ?? "",
      buildbear: "verifyContract",
      phalcon: process.env.PHALCON_API_KEY ?? "",
    },
    customChains: [
      {
        network: "buildbear",
        chainId: 10454,
        urls: {
          apiURL: `https://rpc.buildbear.io/verify/etherscan/${buildbearApiKey}1`,
          browserURL: `https://explorer.buildbear.io/${buildbearApiKey}`,
        },
      },
      {
        network: "phalcon",
        chainId: 1,
        urls: {
          apiURL: process.env.PHALCON_API_URL ?? "",
          browserURL: process.env.PHALCON_BROWSER_URL ?? "",
        },
      },
    ],
  },
  mocha: {
    timeout: 100000000,
  },
  namedAccounts: {
    deployer: {
      default: 0,
      1: 0,
    },
  },
  dependencyCompiler: {
    paths: [
      "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol",
      "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol",
    ],
  },
};

export default config;
