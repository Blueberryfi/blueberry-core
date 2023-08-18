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

  await deploy("ProxyAdmin", {
    from: deployer,
    args: [],
    log: true,
  });
};

export default deploy;
deploy.tags = ["ProxyAdmin"];
