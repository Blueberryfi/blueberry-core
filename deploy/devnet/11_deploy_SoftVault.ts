import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { CONTRACT_NAMES, ADDRESS_DEV } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const protocolConfig = await get(CONTRACT_NAMES.ProtocolConfig);

  const softVaultsInfo: any = {
    USDC: [ADDRESS_DEV.bUSDC, "Interest Bearing USDC", "ibUSDC"],
    ALCX: [ADDRESS_DEV.bALCX, "Interest Bearing ALCX", "ibALCX"],
    OHM: [ADDRESS_DEV.bOHM, "Interest Bearing OHM", "ibOHM"],
    CRV: [ADDRESS_DEV.bCRV, "Interest Bearing CRV", "ibCRV"],
    MIM: [ADDRESS_DEV.bMIM, "Interest Bearing MIM", "ibMIM"],
    BAL: [ADDRESS_DEV.bBAL, "Interest Bearing BAL", "ibBAL"],
    LINK: [ADDRESS_DEV.bLINK, "Interest Bearing LINK", "ibLINK"],
    DAI: [ADDRESS_DEV.bDAI, "Interest Bearing DAI", "ibDAI"],
    ETH: [ADDRESS_DEV.bWETH, "Interest Bearing ETH", "ibETH"],
    WBTC: [ADDRESS_DEV.bWBTC, "Interest Bearing wBTC", "ibwBTC"],
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
