import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const protocolConfig = await get(CONTRACT_NAMES.ProtocolConfig);

  const softVaultsInfo: any = {
    USDC: [ADDRESS.bUSDC, "Interest Bearing USDC", "ibUSDC"],
    ALCX: [ADDRESS.bALCX, "Interest Bearing ALCX", "ibALCX"],
    OHM: [ADDRESS.bOHM, "Interest Bearing OHM", "ibOHM"],
    CRV: [ADDRESS.bCRV, "Interest Bearing CRV", "ibCRV"],
    MIM: [ADDRESS.bMIM, "Interest Bearing MIM", "ibMIM"],
    BAL: [ADDRESS.bBAL, "Interest Bearing BAL", "ibBAL"],
    LINK: [ADDRESS.bLINK, "Interest Bearing LINK", "ibLINK"],
    DAI: [ADDRESS.bDAI, "Interest Bearing DAI", "ibDAI"],
    ETH: [ADDRESS.bWETH, "Interest Bearing ETH", "ibETH"],
    WBTC: [ADDRESS.bWBTC, "Interest Bearing wBTC", "ibwBTC"],
  };

  for (let i = 0; i < Object.keys(softVaultsInfo).length; i += 1) {
    const name = Object.keys(softVaultsInfo)[i];
    const params = softVaultsInfo[name];

    await deploy(name + CONTRACT_NAMES.SoftVault, {
      contract: CONTRACT_NAMES.SoftVault,
      from: deployer,
      log: true,
      waitConfirmations: 1,
      proxy: {
        owner: (await get("ProxyAdmin")).address,
        proxyContract: "TransparentUpgradeableProxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [protocolConfig.address, ...params],
          },
        },
      },
    });
  }
};

export default deploy;
deploy.tags = ["SoftVault"];
