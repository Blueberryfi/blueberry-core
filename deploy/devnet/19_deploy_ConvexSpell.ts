import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { utils } from "ethers";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { ConvexSpell } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const bank = await get(CONTRACT_NAMES.BlueBerryBank);
  const werc20 = await get(CONTRACT_NAMES.WERC20);
  const wconvexPools = await get(CONTRACT_NAMES.WConvexPools);
  const stableOracle = await get(CONTRACT_NAMES.CurveStableOracle);

  const result = await deploy(CONTRACT_NAMES.ConvexSpell, {
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
            wconvexPools.address,
            stableOracle.address,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
          ],
        },
      },
    },
  });

  const ConvexSpellFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.ConvexSpell
  );
  const convexSpell = <ConvexSpell>ConvexSpellFactory.attach(result.address);

  console.log("Adding Strategies to ConvexSpell");
  let tx = await convexSpell.addStrategy(
    ADDRESS.CRV_FRXETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    0,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.CRV_FRXETH,
    ],
    [200000, 200000, 200000, 200000, 200000, 200000]
  );
  await tx.wait(1);
  tx = await convexSpell.addStrategy(
    ADDRESS.CRV_STETH,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    1,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.CRV_STETH,
    ],
    [200000, 200000, 200000, 200000, 200000, 200000]
  );
  await tx.wait(1);
  tx = await convexSpell.addStrategy(
    ADDRESS.CRV_MIM3CRV,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    2,
    [ADDRESS.MIM, ADDRESS.CRV_MIM3CRV],
    [50000, 50000]
  );
  await tx.wait(1);
  tx = await convexSpell.addStrategy(
    ADDRESS.CRV_CVXCRV_CRV,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    3,
    [
      ADDRESS.WBTC,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.CRV_CVXCRV_CRV,
    ],
    [70000, 70000, 70000, 70000, 70000]
  );
  await tx.wait(1);
  tx = await convexSpell.addStrategy(
    ADDRESS.CRV_ALCX_FRAXBP,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    4,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.CRV_ALCX_FRAXBP,
    ],
    [30000, 30000, 30000, 30000, 30000, 30000]
  );
  await tx.wait(1);
  tx = await convexSpell.addStrategy(
    ADDRESS.CRV_OHM_FRAXBP,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    5,
    [
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.LINK,
      ADDRESS.CRV_OHM_FRAXBP,
    ],
    [50000, 50000, 50000, 50000, 50000, 50000]
  );
  await tx.wait(1);
  tx = await convexSpell.addStrategy(
    ADDRESS.CRV,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    6,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI, ADDRESS.CRV],
    [30000, 30000, 30000, 30000, 30000]
  );
  await tx.wait(1);
  tx = await convexSpell.addStrategy(
    ADDRESS.CRV_TriCrypto,
    utils.parseUnits("5000", 18),
    utils.parseUnits("2500000", 18)
  );
  await tx.wait(1);
  tx = await convexSpell.setCollateralsMaxLTVs(
    7,
    [ADDRESS.WBTC, ADDRESS.wstETH, ADDRESS.ETH, ADDRESS.DAI],
    [30000, 30000, 30000, 30000]
  );
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["ConvexSpell"];
