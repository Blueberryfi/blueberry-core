import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { utils } from "ethers";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { IchiSpell } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const bank = await get(CONTRACT_NAMES.BlueBerryBank);
  const werc20 = await get(CONTRACT_NAMES.WERC20);
  const wichiFarm = await get(CONTRACT_NAMES.WIchiFarm);

  const result = await deploy(CONTRACT_NAMES.IchiSpell, {
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
            wichiFarm.address,
            ADDRESS.UNI_V3_ROUTER,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
          ],
        },
      },
    },
  });

  const IchiSpellFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.IchiSpell
  );
  const ichiSpell = <IchiSpell>IchiSpellFactory.attach(result.address);

  console.log("Adding Strategies to IchiSpell");
  let tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ALCX_USDC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("250000", 18)
  );
  await tx.wait(1);

  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_USDC_ALCX,
    utils.parseUnits("5000", 18),
    utils.parseUnits("100000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ALCX_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("250000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ETH_USDC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("5000000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_USDC_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("5000000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_WBTC_USDC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_USDC_WBTC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_OHM_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_LINK_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("1000000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
    8,
    [ADDRESS.LINK, ADDRESS.wstETH, ADDRESS.USDC, ADDRESS.ICHI_VAULT_LINK_ETH],
    [30000, 30000, 30000, 30000]
  );
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_WBTC_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await ichiSpell.addStrategy(
    ADDRESS.ICHI_VAULT_ETH_WBTC,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await ichiSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["IchiSpell"];
