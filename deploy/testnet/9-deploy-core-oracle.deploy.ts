import { ethers, upgrades } from "hardhat";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../../constant";
import { CoreOracle } from "../../typechain-types";
import { deployment, writeDeployments } from '../../utils';

async function main(): Promise<void> {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // const aggregatorOracle = await ethers.getContractAt(CONTRACT_NAMES.AggregatorOracle, deployment.AggregatorOracle);
  // await aggregatorOracle.setMultiPrimarySources(
  //   [
  //     deployment.MockUSDC,
  //     deployment.MockUSDD,
  //     deployment.MockDAI,
  //     deployment.MockWETH,
  //     deployment.MockWBTC,
  //   ], [
  //   ethers.utils.parseEther("1.05"),
  //   ethers.utils.parseEther("1.05"),
  //   ethers.utils.parseEther("1.05"),
  //   ethers.utils.parseEther("1.05"),
  //   ethers.utils.parseEther("1.05"),
  // ], [
  //   [deployment.ChainlinkAdapterOracle],
  //   [deployment.ChainlinkAdapterOracle],
  //   [deployment.ChainlinkAdapterOracle],
  //   [deployment.ChainlinkAdapterOracle],
  //   [deployment.ChainlinkAdapterOracle],
  // ]);

  // const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  // const oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle);
  // await oracle.deployed();

  // console.log("CoreOracle Deployed:", oracle.address);
  // deployment.CoreOracle = oracle.address;
  // writeDeployments(deployment);

  // Set oracle configs
  const oracle = <CoreOracle>await ethers.getContractAt(CONTRACT_NAMES.CoreOracle, deployment.CoreOracle);
  await oracle.setTokenSettings(
    [
      deployment.MockALCX,
    ],
    [
      {
        route: "0x1FBC7d02e39603B3D2EF5764679d461bC00ecA6E",
        liqThreshold: 9000
      },
    ]
  )

  // await oracle.setRoute(
  //   [
  //     deployment.MockIchiV2
  //     // deployment.MockWBTC,
  //     // deployment.MockWETH,
  //     // deployment.MockDAI,
  //     // deployment.MockALCX,
  //     // deployment.MockBAL,
  //     // deployment.MockSUSHI,
  //     // deployment.MockCRV,
  //     // deployment.MockUSDD,
  //   ],
  //   [
  //     // deployment.AggregatorOracle,
  //     // deployment.AggregatorOracle,
  //     // deployment.AggregatorOracle,
  //     // deployment.UniswapV3AdapterOracle,
  //     // deployment.UniswapV3AdapterOracle,
  //     // deployment.UniswapV3AdapterOracle,
  //     deployment.UniswapV3AdapterOracle,
  //     deployment.AggregatorOracle,
  //   ]
  // )
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
