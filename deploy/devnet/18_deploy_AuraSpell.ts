import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { utils } from "ethers";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { AuraSpell } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const bank = await get(CONTRACT_NAMES.BlueBerryBank);
  const werc20 = await get(CONTRACT_NAMES.WERC20);
  const wauraPools = await get(CONTRACT_NAMES.WAuraPools);

  const result = await deploy(CONTRACT_NAMES.AuraSpell, {
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
            wauraPools.address,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
          ],
        },
      },
    },
  });

  const AuraSpellFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.AuraSpell
  );
  const auraSpell = <AuraSpell>AuraSpellFactory.attach(result.address);

  console.log("Adding Strategies to AuraSpell");
  let tx = await auraSpell.addStrategy(
    ADDRESS.BAL_AURA_STABLE,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await auraSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await auraSpell.addStrategy(
    ADDRESS.BAL_ETH_BASKET,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await auraSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
  tx = await auraSpell.addStrategy(
    ADDRESS.BAL_OHM_ETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await auraSpell.setCollateralsMaxLTVs(
    2,
    [ADDRESS.OHM, ADDRESS.ETH, ADDRESS.BAL_OHM_ETH],
    [70000, 70000, 70000]
  );
  await tx.wait(1);
  tx = await auraSpell.addStrategy(
    ADDRESS.BAL_AURA_STABLE,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await auraSpell.setCollateralsMaxLTVs(
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
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["AuraSpell"];
