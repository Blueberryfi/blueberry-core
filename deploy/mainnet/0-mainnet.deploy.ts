import fs from "fs";
import { ethers, upgrades, network } from "hardhat";
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
} from "../../typechain-types";

const deploymentPath = "./deployments";
const deploymentFilePath = `${deploymentPath}/${network.name}.json`;

async function main(): Promise<void> {
  const [deployer] = await ethers.getSigners();

  const deployment = fs.existsSync(deploymentFilePath)
    ? JSON.parse(fs.readFileSync(deploymentFilePath).toString())
    : {};
  const coreOracle = <CoreOracle>(
    await ethers.getContractAt(CONTRACT_NAMES.CoreOracle, deployment.CoreOracle)
  );

  // Ichi Lp Oracle
  const IchiVaultOracle = await ethers.getContractFactory(
    CONTRACT_NAMES.IchiVaultOracle
  );
  const ichiVaultOracle = <IchiVaultOracle>(
    await IchiVaultOracle.deploy(coreOracle.address)
  );
  await ichiVaultOracle.deployed();
  console.log("Ichi Lp Oracle Address:", ichiVaultOracle.address);

  await coreOracle.setRoutes(
    [ADDRESS.ICHI_VAULT_USDC],
    [ichiVaultOracle.address]
  );

  // Bank
  const Config = await ethers.getContractFactory("ProtocolConfig");
  const config = <ProtocolConfig>await upgrades.deployProxy(Config, [deployer]);
  await config.deployed();

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

  // WERC20 of Ichi Vault Lp
  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  const werc20 = <WERC20>await WERC20.deploy();
  await werc20.deployed();

  // WIchiFarm
  const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
  const wichiFarm = <WIchiFarm>(
    await upgrades.deployProxy(WIchiFarm, [ADDRESS.ICHI, ADDRESS.ICHI_FARMING])
  );
  await wichiFarm.deployed();

  // Ichi Vault Spell
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

  const WAuraPools = await ethers.getContractFactory(CONTRACT_NAMES.WAuraPools);
  const waura = <WAuraPools>(
    await upgrades.deployProxy(WAuraPools, [
      ADDRESS.AURA,
      ADDRESS.AURA_BOOSTER,
      ADDRESS.STASH_AURA,
    ])
  );
  await waura.deployed();

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

  const WConvexPools = await ethers.getContractFactory(
    CONTRACT_NAMES.WConvexPools
  );
  const wconvex = <WConvexPools>(
    await upgrades.deployProxy(WConvexPools, [ADDRESS.CVX, ADDRESS.CVX_BOOSTER])
  );
  await wconvex.deployed();

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

  // Deploy CRV spell
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
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
