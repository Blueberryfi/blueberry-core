import fs from "fs";
import { ethers, upgrades, network } from "hardhat";
import { utils } from "ethers";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  BlueBerryBank,
  CoreOracle,
  IchiVaultOracle,
  IchiSpell,
  AuraSpell,
  WAuraPools,
  CurveStableOracle,
  ConvexSpell,
  WConvexPools,
  CurveSpell,
  WCurveGauge,
  ShortLongSpell,
  ProtocolConfig,
  WERC20,
  WIchiFarm,
  SoftVault,
} from "../../typechain-types";

const deploymentPath = "./deployments";
const deploymentFilePath = `${deploymentPath}/${network.name}.json`;

function writeDeployments(deployment: any) {
  if (!fs.existsSync(deploymentPath)) {
    fs.mkdirSync(deploymentPath);
  }
  fs.writeFileSync(deploymentFilePath, JSON.stringify(deployment, null, 2));
}

async function main(): Promise<void> {
  const [deployer] = await ethers.getSigners();

  const deployment = fs.existsSync(deploymentFilePath)
    ? JSON.parse(fs.readFileSync(deploymentFilePath).toString())
    : {};
  const coreOracle = <CoreOracle>(
    await ethers.getContractAt(CONTRACT_NAMES.CoreOracle, deployment.CoreOracle)
  );

  console.log("Deploying UniV3WrappedLib...");
  const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
  const LibInstance = await LinkedLibFactory.deploy();
  await LibInstance.deployed();
  console.log("UniV3WrappedLib Address:", LibInstance.address);
  deployment.UniV3WrappedLib = LibInstance.address;
  writeDeployments(deployment);

  // Ichi Lp Oracle
  console.log("Deploying IchiVaultOracle...");
  const IchiVaultOracle = await ethers.getContractFactory(
    CONTRACT_NAMES.IchiVaultOracle,
    {
      libraries: {
        Univ3WrappedLibContainer: LibInstance.address,
      },
    }
  );
  const ichiVaultOracle = <IchiVaultOracle>(
    await IchiVaultOracle.deploy(coreOracle.address)
  );
  await ichiVaultOracle.deployed();
  console.log("Ichi Lp Oracle Address:", ichiVaultOracle.address);
  deployment.IchiVaultOracle = ichiVaultOracle.address;
  writeDeployments(deployment);

  await ichiVaultOracle.setPriceDeviation(ADDRESS.USDC, 500);
  await ichiVaultOracle.setPriceDeviation(ADDRESS.ALCX, 500);
  await ichiVaultOracle.setPriceDeviation(ADDRESS.ETH, 500);
  await ichiVaultOracle.setPriceDeviation(ADDRESS.WBTC, 500);
  await ichiVaultOracle.setPriceDeviation(ADDRESS.OHM, 500);
  await ichiVaultOracle.setPriceDeviation(ADDRESS.LINK, 500);

  await coreOracle.setRoutes(
    [
      ADDRESS.ICHI_VAULT_USDC,
      ADDRESS.ICHI_VAULT_USDC_ALCX,
      ADDRESS.ICHI_VAULT_ALCX_USDC,
      ADDRESS.ICHI_VAULT_ALCX_ETH,
      ADDRESS.ICHI_VAULT_ETH_USDC,
      ADDRESS.ICHI_VAULT_USDC_ETH,
      ADDRESS.ICHI_VAULT_WBTC_USDC,
      ADDRESS.ICHI_VAULT_USDC_WBTC,
      ADDRESS.ICHI_VAULT_OHM_ETH,
      ADDRESS.ICHI_VAULT_LINK_ETH,
      ADDRESS.ICHI_VAULT_WBTC_ETH,
      ADDRESS.ICHI_VAULT_ETH_WBTC,
    ],
    [
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
      ichiVaultOracle.address,
    ]
  );

  // Bank
  console.log("Deploying ProtocolConfig...");
  const Config = await ethers.getContractFactory("ProtocolConfig");
  const config = <ProtocolConfig>await upgrades.deployProxy(Config, [deployer]);
  await config.deployed();
  console.log("Protocol Config Address:", config.address);
  deployment.ProtocolConfig = config.address;
  writeDeployments(deployment);

  console.log("Deploying Bank...");
  const BlueBerryBank = await ethers.getContractFactory(
    CONTRACT_NAMES.BlueBerryBank
  );
  const bank = <BlueBerryBank>(
    await upgrades.deployProxy(BlueBerryBank, [
      coreOracle.address,
      config.address,
      2000,
    ])
  );
  await bank.deployed();
  console.log("Bank Address:", bank.address);
  deployment.Bank = bank.address;
  writeDeployments(deployment);

  // WERC20 of Ichi Vault Lp
  console.log("Deploying WERC20...");
  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  const werc20 = <WERC20>await WERC20.deploy();
  await werc20.deployed();
  console.log("WERC20 Address:", werc20.address);
  deployment.WERC20 = werc20.address;
  writeDeployments(deployment);

  // WIchiFarm
  console.log("Deploying WIchiFarm...");
  const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
  const wichiFarm = <WIchiFarm>(
    await upgrades.deployProxy(WIchiFarm, [ADDRESS.ICHI, ADDRESS.ICHI_FARMING])
  );
  await wichiFarm.deployed();
  console.log("WIchiFarm Address:", wichiFarm.address);
  deployment.WIchiFarm = wichiFarm.address;
  writeDeployments(deployment);

  // Ichi Vault Spell
  console.log("Deploying IchiSpell...");
  const IchiSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiSpell);
  const ichiSpell = <IchiSpell>(
    await upgrades.deployProxy(IchiSpell, [
      bank.address,
      werc20.address,
      ADDRESS.WETH,
      wichiFarm.address,
      ADDRESS.UNI_V3_ROUTER,
    ])
  );
  await ichiSpell.deployed();
  console.log("IchiSpell Address:", ichiSpell.address);
  deployment.IchiSpell = ichiSpell.address;
  writeDeployments(deployment);

  console.log("Adding Strategies to IchiSpell");
  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ALCX_USDC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("250000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    0,
    [
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ETH,
      ADDRESS.ICHI_VAULT_ALCX_USDC,
    ],
    [30000, 30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_USDC_ALCX,
    utils.parseUnits("5000", 18),
    utils.parseUnits("100000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    1,
    [
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ETH,
      ADDRESS.ICHI_VAULT_USDC_ALCX,
    ],
    [20000, 20000, 20000, 20000, 20000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ALCX_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("250000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    2,
    [
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ETH,
      ADDRESS.ICHI_VAULT_ALCX_ETH,
    ],
    [30000, 30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ETH_USDC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("5000000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    3,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ETH,
      ADDRESS.ICHI_VAULT_ETH_USDC,
    ],
    [30000, 30000, 30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_USDC_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("5000000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    4,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ETH,
      ADDRESS.ICHI_VAULT_USDC_ETH,
    ],
    [30000, 30000, 30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_WBTC_USDC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    5,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ETH,
      ADDRESS.ICHI_VAULT_WBTC_USDC,
    ],
    [30000, 30000, 30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_USDC_WBTC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    6,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ETH,
      ADDRESS.ICHI_VAULT_USDC_WBTC,
    ],
    [30000, 30000, 30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_OHM_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    7,
    [
      ADDRESS.ETH,
      ADDRESS.OHM,
      ADDRESS.wstETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.ICHI_VAULT_OHM_ETH,
    ],
    [50000, 50000, 50000, 50000, 50000, 50000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_LINK_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("1000000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    8,
    [ADDRESS.LINK, ADDRESS.wstETH, ADDRESS.USDC, ADDRESS.ICHI_VAULT_LINK_ETH],
    [30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_WBTC_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    9,
    [
      ADDRESS.ETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.ICHI_VAULT_WBTC_ETH,
    ],
    [30000, 30000, 30000, 30000, 30000, 30000]
  );

  await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ETH_WBTC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await ichiSpell.setCollateralsMaxLTVs(
    10,
    [
      ADDRESS.ETH,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.ICHI_VAULT_ETH_WBTC,
    ],
    [30000, 30000, 30000, 30000, 30000, 30000]
  );

  console.log("Deploying WAuraPools...");
  const WAuraPools = await ethers.getContractFactory(CONTRACT_NAMES.WAuraPools);
  const waura = <WAuraPools>(
    await upgrades.deployProxy(WAuraPools, [
      ADDRESS.AURA,
      ADDRESS.AURA_BOOSTER,
      ADDRESS.STASH_AURA,
    ])
  );
  await waura.deployed();
  console.log("WAuraPools Address:", waura.address);
  deployment.WAuraPools = waura.address;
  writeDeployments(deployment);

  console.log("Deploying AuraSpell...");
  const AuraSpell = await ethers.getContractFactory(CONTRACT_NAMES.AuraSpell);
  const auraSpell = <AuraSpell>(
    await upgrades.deployProxy(AuraSpell, [
      bank.address,
      werc20.address,
      ADDRESS.WETH,
      waura.address,
      ADDRESS.AUGUSTUS_SWAPPER,
      ADDRESS.TOKEN_TRANSFER_PROXY,
    ])
  );
  await auraSpell.deployed();
  console.log("AuraSpell Address:", auraSpell.address);
  deployment.AuraSpell = auraSpell.address;
  writeDeployments(deployment);

  console.log("Adding Strategies to AuraSpell");
  await auraSpell.addStrategy(
    ADDRESS.BAL_AURA_STABLE,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await auraSpell.setCollateralsMaxLTVs(
    0,
    [
      ADDRESS.WBTC,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.BAL,
      ADDRESS.BAL_AURA_STABLE,
    ],
    [70000, 70000, 70000, 70000, 70000, 70000]
  );

  await auraSpell.addStrategy(
    ADDRESS.BAL_ETH_BASKET,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await auraSpell.setCollateralsMaxLTVs(
    1,
    [
      ADDRESS.WBTC,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.BAL_ETH_BASKET,
    ],
    [70000, 70000, 70000, 70000, 70000]
  );

  await auraSpell.addStrategy(
    ADDRESS.BAL_OHM_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await auraSpell.setCollateralsMaxLTVs(
    2,
    [ADDRESS.OHM, ADDRESS.ETH, ADDRESS.BAL_OHM_ETH],
    [70000, 70000, 70000]
  );

  await auraSpell.addStrategy(
    ADDRESS.BAL_AURA_STABLE,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await auraSpell.setCollateralsMaxLTVs(
    3,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.BAL_AURA_STABLE,
    ],
    [70000, 70000, 70000, 70000, 70000, 70000]
  );

  console.log("Deploying CurveStableOracle...");
  const CurveStableOracle = await ethers.getContractFactory(
    CONTRACT_NAMES.CurveStableOracle
  );
  const stableOracle = <CurveStableOracle>(
    await CurveStableOracle.deploy(
      coreOracle.address,
      ADDRESS.CRV_ADDRESS_PROVIDER
    )
  );
  await stableOracle.deployed();
  console.log("CurveStableOracle Address:", stableOracle.address);
  deployment.CurveStableOracle = stableOracle.address;
  writeDeployments(deployment);

  console.log("Deploying WConvexPools...");
  const WConvexPools = await ethers.getContractFactory(
    CONTRACT_NAMES.WConvexPools
  );
  const wconvex = <WConvexPools>(
    await upgrades.deployProxy(WConvexPools, [ADDRESS.CVX, ADDRESS.CVX_BOOSTER])
  );
  await wconvex.deployed();
  console.log("WConvexPools Address:", wconvex.address);
  deployment.WConvexPools = wconvex.address;
  writeDeployments(deployment);

  console.log("Deploying ConvexSpell...");
  const ConvexSpell = await ethers.getContractFactory(
    CONTRACT_NAMES.ConvexSpell
  );
  const convexSpell = <ConvexSpell>(
    await upgrades.deployProxy(ConvexSpell, [
      bank.address,
      werc20.address,
      ADDRESS.WETH,
      wconvex.address,
      stableOracle.address,
      ADDRESS.AUGUSTUS_SWAPPER,
      ADDRESS.TOKEN_TRANSFER_PROXY,
    ])
  );
  await convexSpell.deployed();
  console.log("ConvexSpell Address:", convexSpell.address);
  deployment.ConvexSpell = convexSpell.address;
  writeDeployments(deployment);

  console.log("Deploying WCurveGauge...");
  const WCurveGauge = await ethers.getContractFactory(
    CONTRACT_NAMES.WCurveGauge
  );
  const wgauge = <WCurveGauge>(
    await upgrades.deployProxy(WCurveGauge, [
      ADDRESS.CRV,
      ADDRESS.CRV_REGISTRY,
      ADDRESS.CRV_GAUGE_CONTROLLER,
    ])
  );
  await wgauge.deployed();
  console.log("WCurveGauge Address:", wgauge.address);
  deployment.WCurveGauge = wgauge.address;
  writeDeployments(deployment);

  // Deploy CRV spell
  console.log("Deploying CurveSpell...");
  const CurveSpell = await ethers.getContractFactory(CONTRACT_NAMES.CurveSpell);
  const curveSpell = <CurveSpell>(
    await upgrades.deployProxy(CurveSpell, [
      bank.address,
      werc20.address,
      ADDRESS.WETH,
      wgauge.address,
      stableOracle.address,
      ADDRESS.AUGUSTUS_SWAPPER,
      ADDRESS.TOKEN_TRANSFER_PROXY,
    ])
  );
  await curveSpell.deployed();
  console.log("CurveSpell Address:", curveSpell.address);
  deployment.CurveSpell = curveSpell.address;
  writeDeployments(deployment);

  console.log("Deploying ShortLongSpell...");
  const ShortLongSpell = await ethers.getContractFactory(
    CONTRACT_NAMES.ShortLongSpell
  );
  const shortLongSpell = <ShortLongSpell>(
    await upgrades.deployProxy(ShortLongSpell, [
      bank.address,
      werc20.address,
      ADDRESS.WETH,
      ADDRESS.AUGUSTUS_SWAPPER,
      ADDRESS.TOKEN_TRANSFER_PROXY,
    ])
  );
  await shortLongSpell.deployed();
  console.log("ShortLongSpell Address:", shortLongSpell.address);
  deployment.ShortLongSpell = shortLongSpell.address;
  writeDeployments(deployment);

  console.log("Adding Strategies to ShortLongSpell");
  console.log("Deploying DAI SoftVault...");
  const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
  const daiSoftVault = <SoftVault>(
    await upgrades.deployProxy(SoftVault, [
      config.address,
      ADDRESS.bDAI,
      "Interest Bearing DAI",
      "ibDAI",
    ])
  );
  await daiSoftVault.deployed();
  console.log("DAI SoftVault Address:", daiSoftVault.address);
  deployment.DAISoftVault = daiSoftVault.address;
  writeDeployments(deployment);

  await shortLongSpell.addStrategy(
    daiSoftVault.address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    0,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI],
    [50000, 50000, 50000, 50000]
  );

  console.log("Deploying ETH SoftVault...");
  const ethSoftVault = <SoftVault>(
    await upgrades.deployProxy(SoftVault, [
      config.address,
      ADDRESS.bWETH,
      "Interest Bearing ETH",
      "ibETH",
    ])
  );
  await ethSoftVault.deployed();
  console.log("ETH SoftVault Address:", ethSoftVault.address);
  deployment.ETHSoftVault = ethSoftVault.address;
  writeDeployments(deployment);

  await shortLongSpell.addStrategy(
    ethSoftVault.address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    1,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI],
    [10000, 10000, 10000, 10000]
  );

  await shortLongSpell.addStrategy(
    ethSoftVault.address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    2,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.DAI],
    [50000, 50000, 50000]
  );

  console.log("Deploying wBTC SoftVault...");
  const wbtcSoftVault = <SoftVault>(
    await upgrades.deployProxy(SoftVault, [
      config.address,
      ADDRESS.bWBTC,
      "Interest Bearing wBTC",
      "ibwBTC",
    ])
  );
  await wbtcSoftVault.deployed();
  console.log("wBTC SoftVault Address:", wbtcSoftVault.address);
  deployment.WBTCSoftVault = wbtcSoftVault.address;
  writeDeployments(deployment);

  await shortLongSpell.addStrategy(
    wbtcSoftVault.address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    3,
    [ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI],
    [50000, 50000, 50000]
  );

  await shortLongSpell.addStrategy(
    daiSoftVault.address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    4,
    [ADDRESS.WBTC, ADDRESS.DAI, ADDRESS.ETH],
    [50000, 50000, 50000]
  );

  console.log("Deploying LINK SoftVault...");
  const linkSoftVault = <SoftVault>(
    await upgrades.deployProxy(SoftVault, [
      config.address,
      ADDRESS.bLINK,
      "Interest Bearing LINK",
      "ibLINK",
    ])
  );
  await linkSoftVault.deployed();
  console.log("wBTC SoftVault Address:", linkSoftVault.address);
  deployment.WBTCSoftVault = linkSoftVault.address;
  writeDeployments(deployment);

  await shortLongSpell.addStrategy(
    linkSoftVault.address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    5,
    [ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI, ADDRESS.WBTC],
    [50000, 50000, 50000, 50000]
  );

  await shortLongSpell.addStrategy(
    daiSoftVault.address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    6,
    [ADDRESS.WBTC, ADDRESS.DAI, ADDRESS.ETH],
    [50000, 50000, 50000]
  );
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
