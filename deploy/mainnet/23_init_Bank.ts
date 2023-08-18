import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { BlueBerryBank } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { get },
  } = hre;
  const werc20 = await get(CONTRACT_NAMES.WERC20);
  const hardVault = await get(CONTRACT_NAMES.HardVault);

  const BlueBerryBankFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.BlueBerryBank
  );
  const bank = <BlueBerryBank>(
    BlueBerryBankFactory.attach(
      (await get(CONTRACT_NAMES.BlueBerryBank)).address
    )
  );

  let tx = await bank.whitelistSpells(
    [
      (await get(CONTRACT_NAMES.AuraSpell)).address,
      (await get(CONTRACT_NAMES.ConvexSpell)).address,
      (await get(CONTRACT_NAMES.IchiSpell)).address,
      (await get(CONTRACT_NAMES.CurveSpell)).address,
      (await get(CONTRACT_NAMES.ShortLongSpell)).address,
    ],
    [true, true, true, true, true]
  );
  await tx.wait(1);
  tx = await bank.whitelistTokens(
    [
      ADDRESS.ALCX,
      ADDRESS.DAI,
      ADDRESS.USDC,
      ADDRESS.WETH,
      ADDRESS.ETH,
      ADDRESS.WBTC,
      ADDRESS.OHM,
      ADDRESS.LINK,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.BAL,
    ],
    [true, true, true, true, true, true, true, true, true, true, true]
  );
  await tx.wait(1);
  tx = await bank.whitelistERC1155(
    [
      werc20.address,
      (await get(CONTRACT_NAMES.WIchiFarm)).address,
      (await get(CONTRACT_NAMES.WAuraPools)).address,
      (await get(CONTRACT_NAMES.WConvexPools)).address,
      (await get(CONTRACT_NAMES.WCurveGauge)).address,
    ],
    true
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.ALCX,
    (
      await get("ALCXSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.DAI,
    (
      await get("DAISoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.USDC,
    (
      await get("USDCSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.ETH,
    (
      await get("ETHSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.WBTC,
    (
      await get("WBTCSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.OHM,
    (
      await get("OHMSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.LINK,
    (
      await get("LINKSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.CRV,
    (
      await get("CRVSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.MIM,
    (
      await get("MIMSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
  tx = await bank.addBank(
    ADDRESS.BAL,
    (
      await get("BALSoftVault")
    ).address,
    hardVault.address,
    8500
  );
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["InitBank"];
