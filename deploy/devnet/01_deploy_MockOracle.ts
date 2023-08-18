import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { MockOracle } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const result = await deploy(CONTRACT_NAMES.MockOracle, {
    from: deployer,
    log: true,
  });

  const MockOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.MockOracle
  );
  const mockOracle = <MockOracle>MockOracleFactory.attach(result.address);

  console.log("Setting up mock prices");
  const tx = await mockOracle.setPrice(
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
      100000000, 100000000, 70000000, 98000000, 700000000, 2900000000000,
      190000000000, 190000000000, 1000000000, 1400000000, 210000000000,
      450000000,
    ]
  );

  await tx.wait(1);
};

export default deploy;
deploy.tags = ["MockOracle"];
