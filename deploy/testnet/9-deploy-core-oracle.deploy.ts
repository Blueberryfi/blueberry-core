import { ethers, upgrades } from "hardhat";
import { CONTRACT_NAMES } from "../../constant";
import { CoreOracle } from "../../typechain-types";
import { deployment, writeDeployments } from '../../utils';

async function main(): Promise<void> {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const aggregatorOracle = await ethers.getContractAt(CONTRACT_NAMES.AggregatorOracle, deployment.AggregatorOracle);
  await aggregatorOracle.setMultiPrimarySources(
    [
      deployment.MockUSDC,
      deployment.MockUSDD,
      deployment.MockDAI,
      deployment.MockWETH,
      deployment.MockWBTC,
    ], [
    ethers.utils.parseEther("1.05"),
    ethers.utils.parseEther("1.05"),
    ethers.utils.parseEther("1.05"),
    ethers.utils.parseEther("1.05"),
    ethers.utils.parseEther("1.05"),
  ], [
    [deployment.ChainlinkAdapterOracle],
    [deployment.ChainlinkAdapterOracle],
    [deployment.ChainlinkAdapterOracle],
    [deployment.ChainlinkAdapterOracle],
    [deployment.ChainlinkAdapterOracle],
  ]);
  return;

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  const oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle);
  await oracle.deployed();

  console.log("CoreOracle Deployed:", oracle.address);
  deployment.CoreOracle = oracle.address;
  writeDeployments(deployment);

  // Set oracle configs
  // const oracle = <CoreOracle>await ethers.getContractAt(CONTRACT_NAMES.CoreOracle, deployment.CoreOracle);
  await oracle.setTokenSettings(
    [
      "0xaE6F9D934d75E7ef5930A3c8817f6B61565A40c2",
      "0xe3166B3a0fB754360bB8Ac0177BdaD26827b971c",
      "0xe768eb7adF7b555FA3726e17eb0595c9850cCBb9",
      "0x745229756e606C88194be866B789A7a9d90BDEc5",
      "0xBF03f7CA2B10B22677BB4F48B1ADC22EC1a32620"
    ],
    [
      {
        route: "0x1FBC7d02e39603B3D2EF5764679d461bC00ecA6E",
        liqThreshold: 8500
      },
      {
        route: "0xA2f423d048bdA5AaC35B8b4bcbD42cd6F32Da461",
        liqThreshold: 9000
      },
      {
        route: "0x213F12D565806868E9879F92f1a06bA4c4cEE44c",
        liqThreshold: 10000
      },
      {
        route: "0x1FBC7d02e39603B3D2EF5764679d461bC00ecA6E",
        liqThreshold: 8500
      },
      {
        route: "0x213F12D565806868E9879F92f1a06bA4c4cEE44c",
        liqThreshold: 10000
      },
    ]
  )
  await oracle.setRoute(
    [
      deployment.MockWBTC,
      deployment.MockWETH,
      deployment.MockDAI,
      deployment.MockALCX,
      deployment.MockBAL,
      deployment.MockSUSHI,
      deployment.MockCRV,
      deployment.MockUSDD,
    ],
    [
      deployment.AggregatorOracle,
      deployment.AggregatorOracle,
      deployment.AggregatorOracle,
      deployment.UniswapV3AdapterOracle,
      deployment.UniswapV3AdapterOracle,
      deployment.UniswapV3AdapterOracle,
      deployment.UniswapV3AdapterOracle,
      deployment.AggregatorOracle,
    ]
  )
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
