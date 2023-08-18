import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACT_NAMES } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  await deploy(CONTRACT_NAMES.WERC20, {
    from: deployer,
    log: true,
    args: [],
  });
};

export default deploy;
deploy.tags = ["WERC20"];
