import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { AggregatorOracle } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const result = await deploy(CONTRACT_NAMES.AggregatorOracle, {
    from: deployer,
    log: true,
  });

  const AggregatorOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.AggregatorOracle
  );
  const aggregatorOracle = <AggregatorOracle>(
    AggregatorOracleFactory.attach(result.address)
  );

  const bandOracle = await get(CONTRACT_NAMES.BandAdapterOracle);
  const chainlinkOracle = await get(CONTRACT_NAMES.ChainlinkAdapterOracle);

  console.log("Setting up Primary Sources\nMax Price Deviation: 5%");
  const tx = await aggregatorOracle.setMultiPrimarySources(
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

  await tx.wait(1);
};

export default deploy;
deploy.tags = ["AggregatorOracle"];
