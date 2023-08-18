import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { UniswapV3AdapterOracle } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const result = await deploy(CONTRACT_NAMES.UniswapV3AdapterOracle, {
    from: deployer,
    args: [(await get(CONTRACT_NAMES.AggregatorOracle)).address],
    libraries: {
      UniV3WrappedLibContainer: (await get("UniV3WrappedLib")).address,
    },
    log: true,
  });

  const UniswapV3AdapterOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.UniswapV3AdapterOracle,
    {
      libraries: {
        UniV3WrappedLibContainer: (await get("UniV3WrappedLib")).address,
      },
    }
  );
  const uniswapV3AdapterOracle = <UniswapV3AdapterOracle>(
    UniswapV3AdapterOracleFactory.attach(result.address)
  );

  let tx = await uniswapV3AdapterOracle.setStablePools(
    [ADDRESS.ICHI],
    [ADDRESS.UNI_V3_ICHI_USDC]
  );
  await tx.wait(1);
  tx = await uniswapV3AdapterOracle.setTimeGap([ADDRESS.ICHI], [3600]); // 1 hours ago
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["UniswapV3AdapterOracle"];
