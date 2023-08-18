import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  await deploy(CONTRACT_NAMES.WAuraPools, {
    from: deployer,
    log: true,
    waitConfirmations: 1,
    proxy: {
      owner: (await get("ProxyAdmin")).address,
      proxyContract: "TransparentUpgradeableProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [ADDRESS.AURA, ADDRESS.AURA_BOOSTER, ADDRESS.STASH_AURA],
        },
      },
    },
  });
};

export default deploy;
deploy.tags = ["WAuraPools"];
