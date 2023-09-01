import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { run } from "hardhat";
import { CONTRACT_NAMES } from "../../constant";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { get },
  } = hre;

  const contracts: any[] = [
    "ProxyAdmin",
    CONTRACT_NAMES.MockOracle,
    CONTRACT_NAMES.AggregatorOracle,
    "UniV3WrappedLib",
    {
      name: CONTRACT_NAMES.UniswapV3AdapterOracle,
      libraries: {
        UniV3WrappedLibContainer: (await get("UniV3WrappedLib")).address,
      },
    },
    {
      name: CONTRACT_NAMES.CoreOracle,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.ProtocolConfig,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.IchiVaultOracle,
      isProxy: true,
    },
    CONTRACT_NAMES.CurveStableOracle,
    {
      name: CONTRACT_NAMES.BlueBerryBank,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.HardVault,
      isProxy: true,
    },
    {
      name: "USDCSoftVault",
      isProxy: true,
    },
    {
      name: "ALCXSoftVault",
      isProxy: true,
    },
    {
      name: "OHMSoftVault",
      isProxy: true,
    },
    {
      name: "CRVSoftVault",
      isProxy: true,
    },
    {
      name: "MIMSoftVault",
      isProxy: true,
    },
    {
      name: "BALSoftVault",
      isProxy: true,
    },
    {
      name: "LINKSoftVault",
      isProxy: true,
    },
    {
      name: "DAISoftVault",
      isProxy: true,
    },
    {
      name: "ETHSoftVault",
      isProxy: true,
    },
    {
      name: "WBTCSoftVault",
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.WERC20,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.WIchiFarm,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.WAuraPools,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.WConvexPools,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.WCurveGauge,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.IchiSpell,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.AuraSpell,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.ConvexSpell,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.CurveSpell,
      isProxy: true,
    },
    {
      name: CONTRACT_NAMES.ShortLongSpell,
      isProxy: true,
    },
  ];

  for (let i = 0; i < contracts.length; i += 1) {
    const contract = contracts[i];
    const name = contract.name ? contract.name : contract;
    const isProxy = !!contract.isProxy;
    const libraries = contract.libraries || undefined;
    console.log(`Verify ${name}`);

    const deployment = await get(name);

    if (isProxy) {
      console.log(`Verify ${name}_Proxy`);
      await run("verify:verify", {
        address: deployment.address,
        constructorArguments: deployment.args,
      });

      const implDeployment = await get(name + "_Implementation");
      console.log(`Verify ${name}_Implementation`);
      await run("verify:verify", {
        address: implDeployment.address,
      });
    } else {
      await run("verify:verify", {
        address: deployment.address,
        constructorArguments: deployment.args,
        libraries,
      });
    }
  }
};

export default deploy;
deploy.tags = ["VerifyCode"];
