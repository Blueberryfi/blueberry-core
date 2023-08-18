import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACT_NAMES } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  await deploy(CONTRACT_NAMES.ProtocolConfig, {
    from: deployer,
    log: true,
    waitConfirmations: 1,
    proxy: {
      owner: (await get("ProxyAdmin")).address,
      proxyContract: "TransparentUpgradeableProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [deployer],
        },
      },
    },
  });
};

export default deploy;
deploy.tags = ["ProtocolConfig"];
