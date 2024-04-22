import '@typechain/hardhat';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import 'solidity-coverage';
import 'hardhat-abi-exporter';
// import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';
import '@openzeppelin/hardhat-upgrades';
import { HardhatUserConfig } from 'hardhat/config';
import dotenv from 'dotenv';

dotenv.config();

const config: HardhatUserConfig = {
  typechain: {
    target: 'ethers-v5',
  },
  solidity: {
    compilers: [
      {
        version: '0.8.22',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.7.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.5.16',
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
      accounts: {
        accountsBalance: '1000000000000000000000000',
      },
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
        blockNumber: 18695050,
      },
    },
  },
  abiExporter: {
    path: './abi',
    runOnCompile: true,
    clear: true,
    flat: false,
    spacing: 2,
    except: ['IBaseOracle'],
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
