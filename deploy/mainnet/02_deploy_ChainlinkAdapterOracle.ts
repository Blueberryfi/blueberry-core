import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { ChainlinkAdapterOracle } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const result = await deploy(CONTRACT_NAMES.ChainlinkAdapterOracle, {
    from: deployer,
    args: [ADDRESS.ChainlinkRegistry],
    log: true,
  });

  const ChainlinkAdapterOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.ChainlinkAdapterOracle
  );
  const chainlinkOracle = <ChainlinkAdapterOracle>(
    ChainlinkAdapterOracleFactory.attach(result.address)
  );

  console.log(
    "Setting up USDC config on Chainlink Oracle\nMax Delay Times: 129900s"
  );
  let tx = await chainlinkOracle.setTimeGap(
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
  await tx.wait(1);
  tx = await chainlinkOracle.setTokenRemappings(
    [ADDRESS.WBTC, ADDRESS.WETH],
    [ADDRESS.CHAINLINK_BTC, ADDRESS.CHAINLINK_ETH]
  );
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["ChainlinkAdapterOracle"];
