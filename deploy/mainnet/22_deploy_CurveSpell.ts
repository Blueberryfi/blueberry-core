import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const bank = await get(CONTRACT_NAMES.BlueBerryBank);
  const werc20 = await get(CONTRACT_NAMES.WERC20);
  const wgauge = await get(CONTRACT_NAMES.WCurveGauge);
  const stableOracle = await get(CONTRACT_NAMES.CurveStableOracle);

  await deploy(CONTRACT_NAMES.CurveSpell, {
    from: deployer,
    log: true,
    waitConfirmations: 1,
    proxy: {
      owner: (await get("ProxyAdmin")).address,
      proxyContract: "TransparentUpgradeableProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            bank.address,
            werc20.address,
            ADDRESS.WETH,
            wgauge.address,
            stableOracle.address,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
          ],
        },
      },
    },
  });
};

export default deploy;
deploy.tags = ["CurveSpell"];
