import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { utils } from "ethers";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { ShortLongSpell } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const bank = await get(CONTRACT_NAMES.BlueBerryBank);
  const werc20 = await get(CONTRACT_NAMES.WERC20);

  const result = await deploy(CONTRACT_NAMES.ShortLongSpell, {
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
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
          ],
        },
      },
    },
  });

  const ShortLongSpellFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.ShortLongSpell
  );
  const shortLongSpell = <ShortLongSpell>(
    ShortLongSpellFactory.attach(result.address)
  );

  console.log("Adding Strategies to ShortLongSpell");
  let tx = await shortLongSpell.addStrategy(
    (
      await get("DAISoftVault")
    ).address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await tx.wait(1);
  tx = await shortLongSpell.setCollateralsMaxLTVs(
    0,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI],
    [50000, 50000, 50000, 50000]
  );
  await tx.wait(1);
  tx = await shortLongSpell.addStrategy(
    (
      await get("ETHSoftVault")
    ).address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await tx.wait(1);
  tx = await shortLongSpell.setCollateralsMaxLTVs(
    1,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI],
    [10000, 10000, 10000, 10000]
  );
  await tx.wait(1);
  tx = await shortLongSpell.addStrategy(
    (
      await get("ETHSoftVault")
    ).address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await tx.wait(1);
  tx = await shortLongSpell.setCollateralsMaxLTVs(
    2,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.DAI],
    [50000, 50000, 50000]
  );
  await tx.wait(1);
  tx = await shortLongSpell.addStrategy(
    (
      await get("WBTCSoftVault")
    ).address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await tx.wait(1);
  tx = await shortLongSpell.setCollateralsMaxLTVs(
    3,
    [ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI],
    [50000, 50000, 50000]
  );
  await tx.wait(1);
  tx = await shortLongSpell.addStrategy(
    (
      await get("DAISoftVault")
    ).address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await tx.wait(1);
  tx = await shortLongSpell.setCollateralsMaxLTVs(
    4,
    [ADDRESS.WBTC, ADDRESS.DAI, ADDRESS.ETH],
    [50000, 50000, 50000]
  );
  await tx.wait(1);
  tx = await shortLongSpell.addStrategy(
    (
      await get("LINKSoftVault")
    ).address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await tx.wait(1);
  tx = await shortLongSpell.setCollateralsMaxLTVs(
    5,
    [ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI, ADDRESS.WBTC],
    [50000, 50000, 50000, 50000]
  );
  await tx.wait(1);
  tx = await shortLongSpell.addStrategy(
    (
      await get("DAISoftVault")
    ).address,
    utils.parseUnits("5000", 18),
    utils.parseUnits("25000", 18)
  );
  await tx.wait(1);
  tx = await shortLongSpell.setCollateralsMaxLTVs(
    6,
    [ADDRESS.WBTC, ADDRESS.DAI, ADDRESS.ETH],
    [50000, 50000, 50000]
  );
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["ShortLongSpell"];
