import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { IchiVaultOracle, CoreOracle } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const result = await deploy(CONTRACT_NAMES.IchiVaultOracle, {
    from: deployer,
    args: [(await get(CONTRACT_NAMES.AggregatorOracle)).address],
    libraries: {
      UniV3WrappedLibContainer: (await get("UniV3WrappedLib")).address,
    },
    log: true,
  });

  const IchiVaultOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.IchiVaultOracle,
    {
      libraries: {
        UniV3WrappedLibContainer: (await get("UniV3WrappedLib")).address,
      },
    }
  );
  const ichiVaultOracle = <IchiVaultOracle>(
    IchiVaultOracleFactory.attach(result.address)
  );

  let tx = await ichiVaultOracle.setPriceDeviation(ADDRESS.USDC, 500);
  await tx.wait(1);
  tx = await ichiVaultOracle.setPriceDeviation(ADDRESS.ALCX, 500);
  await tx.wait(1);
  tx = await ichiVaultOracle.setPriceDeviation(ADDRESS.ETH, 500);
  await tx.wait(1);
  tx = await ichiVaultOracle.setPriceDeviation(ADDRESS.WBTC, 500);
  await tx.wait(1);
  tx = await ichiVaultOracle.setPriceDeviation(ADDRESS.OHM, 500);
  await tx.wait(1);
  tx = await ichiVaultOracle.setPriceDeviation(ADDRESS.LINK, 500);
  await tx.wait(1);

  const CoreOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.CoreOracle
  );
  const coreOracle = <CoreOracle>(
    CoreOracleFactory.attach((await get(CONTRACT_NAMES.CoreOracle)).address)
  );

  tx = await coreOracle.setRoutes(
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
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["IchiVaultOracle"];
