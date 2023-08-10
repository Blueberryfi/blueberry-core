import fs from "fs";
import { ethers, network, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  AggregatorOracle,
  BandAdapterOracle,
  ChainlinkAdapterOracle,
  CoreOracle,
  UniswapV3AdapterOracle,
  MockOracle,
} from "../../typechain-types";

const deploymentPath = "./deployments";
const deploymentFilePath = `${deploymentPath}/${network.name}.json`;

function writeDeployments(deployment: any) {
  if (!fs.existsSync(deploymentPath)) {
    fs.mkdirSync(deploymentPath);
  }
  fs.writeFileSync(deploymentFilePath, JSON.stringify(deployment, null, 2));
}

async function main(): Promise<void> {
  const deployment = fs.existsSync(deploymentFilePath)
    ? JSON.parse(fs.readFileSync(deploymentFilePath).toString())
    : {};

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // Band Adapter Oracle
  const BandAdapterOracle = await ethers.getContractFactory(
    "BandAdapterOracle"
  );
  const bandOracle = <BandAdapterOracle>(
    await BandAdapterOracle.deploy(ADDRESS.BandStdRef)
  );
  await bandOracle.deployed();
  console.log("Band Oracle Address:", bandOracle.address);
  deployment.BandAdapterOracle = bandOracle.address;
  writeDeployments(deployment);

  console.log(
    "Setting up Token configs on Band Oracle\nMax Delay Times: 1 day 12 hours"
  );
  await bandOracle.setTimeGap(
    [
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.WBTC,
      ADDRESS.WETH,
      ADDRESS.OHM,
      ADDRESS.ALCX,
      ADDRESS.wstETH,
      ADDRESS.BAL,
    ],
    [
      129600, 129600, 129600, 129600, 129600, 129600, 129600, 129600, 129600,
      129600, 129600,
    ]
  );
  await bandOracle.setSymbols(
    [
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.WBTC,
      ADDRESS.WETH,
      ADDRESS.OHM,
      ADDRESS.ALCX,
      ADDRESS.wstETH,
      ADDRESS.BAL,
    ],
    [
      "USDC",
      "DAI",
      "CRV",
      "MIM",
      "LINK",
      "WBTC",
      "ETH",
      "OHM",
      "ALCX",
      "wstETH",
      "BAL",
    ]
  );

  // Chainlink Adapter Oracle
  const ChainlinkAdapterOracle = await ethers.getContractFactory(
    "ChainlinkAdapterOracle"
  );
  const chainlinkOracle = <ChainlinkAdapterOracle>(
    await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry)
  );
  await chainlinkOracle.deployed();
  console.log("Chainlink Oracle Address:", chainlinkOracle.address);
  deployment.ChainlinkAdapterOracle = chainlinkOracle.address;
  writeDeployments(deployment);

  console.log(
    "Setting up USDC config on Chainlink Oracle\nMax Delay Times: 129900s"
  );
  await chainlinkOracle.setTimeGap(
    [
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.WBTC,
      ADDRESS.WETH,
      ADDRESS.OHM,
      ADDRESS.ALCX,
      ADDRESS.wstETH,
      ADDRESS.BAL,
    ],
    [
      129600, 129600, 129600, 129600, 129600, 129600, 129600, 129600, 129600,
      129600, 129600,
    ]
  );
  await chainlinkOracle.setTokenRemappings(
    [ADDRESS.WBTC, ADDRESS.WETH],
    [ADDRESS.CHAINLINK_BTC, ADDRESS.CHAINLINK_ETH]
  );

  // Aggregator Oracle
  const AggregatorOracle = await ethers.getContractFactory("AggregatorOracle");
  const aggregatorOracle = <AggregatorOracle>await AggregatorOracle.deploy();
  await aggregatorOracle.deployed();
  console.log("Aggregator Oracle Address:", aggregatorOracle.address);
  deployment.AggregatorOracle = aggregatorOracle.address;
  writeDeployments(deployment);

  console.log("Setting up Primary Sources\nMax Price Deviation: 5%");
  await aggregatorOracle.setMultiPrimarySources(
    [
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.WBTC,
      ADDRESS.WETH,
      ADDRESS.OHM,
      ADDRESS.ALCX,
      ADDRESS.wstETH,
      ADDRESS.BAL,
    ],
    [500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500],
    [
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
      [bandOracle.address, chainlinkOracle.address],
    ]
  );

  console.log("Deploying UniV3WrappedLib...");
  const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
  const LibInstance = await LinkedLibFactory.deploy();
  await LibInstance.deployed();
  console.log("UniV3WrappedLib Address:", LibInstance.address);
  deployment.UniV3WrappedLib = LibInstance.address;
  writeDeployments(deployment);

  // Uni V3 Adapter Oracle
  const UniswapV3AdapterOracle = await ethers.getContractFactory(
    "UniswapV3AdapterOracle",
    {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    }
  );
  const uniV3Oracle = <UniswapV3AdapterOracle>(
    await UniswapV3AdapterOracle.deploy(aggregatorOracle.address)
  );
  await uniV3Oracle.deployed();
  console.log("Uni V3 Oracle Address:", uniV3Oracle.address);
  deployment.UniswapV3AdapterOracle = uniV3Oracle.address;
  writeDeployments(deployment);

  await uniV3Oracle.setStablePools([ADDRESS.ICHI], [ADDRESS.UNI_V3_ICHI_USDC]);
  await uniV3Oracle.setTimeGap([ADDRESS.ICHI], [3600]); // 1 hours ago

  // Core Oracle
  const CoreOracle = await ethers.getContractFactory("CoreOracle");
  const coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, []);
  await coreOracle.deployed();
  console.log("Core Oracle Address:", coreOracle.address);
  deployment.CoreOracle = coreOracle.address;
  writeDeployments(deployment);

  await coreOracle.setRoutes(
    [
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.WBTC,
      ADDRESS.WETH,
      ADDRESS.ETH,
      ADDRESS.OHM,
      ADDRESS.ALCX,
      ADDRESS.wstETH,
      ADDRESS.BAL,
      ADDRESS.ICHI,
    ],
    [
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      uniV3Oracle.address,
    ]
  );
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
