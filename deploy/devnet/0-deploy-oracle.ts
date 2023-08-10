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

  // Mock Oracle
  const MockOracle = await ethers.getContractFactory(
    CONTRACT_NAMES.MockOracle
  );
  const mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  console.log("Mock Oracle Address:", mockOracle.address);
  deployment.MockOracle = mockOracle.address;
  writeDeployments(deployment);

  console.log("Setting up mock prices");
  await mockOracle.setPrice(
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
    ],
    [
      100000000,
      100000000,
      70000000,
      98000000,
      700000000,
      2900000000000,
      190000000000,
      190000000000,
      1000000000,
      1400000000,
      210000000000,
      450000000,
    ]
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
      ADDRESS.ETH,
      ADDRESS.OHM,
      ADDRESS.ALCX,
      ADDRESS.wstETH,
      ADDRESS.BAL,
    ],
    [500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500],
    [
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
      [mockOracle.address],
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
