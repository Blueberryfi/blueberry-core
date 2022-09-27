import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import '@openzeppelin/hardhat-upgrades';
import 'solidity-coverage';
import 'hardhat-abi-exporter';
import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import 'hardhat-docgen'
import '@hardhat-docgen/core'
import '@hardhat-docgen/markdown'
import { HardhatUserConfig } from 'hardhat/config';
import dotenv from 'dotenv';

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

const config: HardhatUserConfig = {
  typechain: {
    target: 'ethers-v5',
  },
  solidity: {
    compilers: [
      {
        version: '0.8.9',
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
        url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyapi}`,
        blockNumber: 15542853,
      }
    },
    mainnet: {
      accounts: [deployAccountKey],
      chainId: 1,
      url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyapi}`,
      timeout: 200000,
    },
    goerli: {
      accounts: [deployAccountKey],
      chainId: 5,
      url: `https://eth-goerli.alchemyapi.io/v2/${alchemyapi}`,
      timeout: 200000,
    },
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
  docgen: {
    path: './docs',
    clear: true,
    runOnCompile: false,
    except: ['/test/*', '/mock/*', '/hardhat-proxy/*'],
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};

export default config;
