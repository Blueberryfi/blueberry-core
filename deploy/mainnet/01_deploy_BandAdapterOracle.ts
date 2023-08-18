import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { BandAdapterOracle } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const result = await deploy(CONTRACT_NAMES.BandAdapterOracle, {
    from: deployer,
    args: [ADDRESS.BandStdRef],
    log: true,
  });

  const BandAdapterOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.BandAdapterOracle
  );
  const bandOracle = <BandAdapterOracle>(
    BandAdapterOracleFactory.attach(result.address)
  );

  console.log(
    "Setting up Token configs on Band Oracle\nMax Delay Times: 1 day 12 hours"
  );
  let tx = await bandOracle.setTimeGap(
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
  tx = await bandOracle.setSymbols(
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
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["BandAdapterOracle"];
