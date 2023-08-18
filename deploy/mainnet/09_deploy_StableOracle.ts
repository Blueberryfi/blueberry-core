import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const coreOracle = await get(CONTRACT_NAMES.CoreOracle);
  await deploy(CONTRACT_NAMES.CurveStableOracle, {
    from: deployer,
    log: true,
    args: [coreOracle.address, ADDRESS.CRV_ADDRESS_PROVIDER],
  });
};

export default deploy;
deploy.tags = ["CurveStableOracle"];
