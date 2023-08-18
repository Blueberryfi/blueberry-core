import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { CONTRACT_NAMES, ADDRESS } from "../../constant";
import { CoreOracle } from "../../typechain-types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;
  const { deployer } = await getNamedAccounts();

  const result = await deploy(CONTRACT_NAMES.CoreOracle, {
    from: deployer,
    log: true,
    waitConfirmations: 1,
    proxy: {
      owner: (await get("ProxyAdmin")).address,
      proxyContract: "TransparentUpgradeableProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [],
        },
      },
    },
  });

  const CoreOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.CoreOracle
  );
  const coreOracle = <CoreOracle>CoreOracleFactory.attach(result.address);

  const aggregatorOracle = await get(CONTRACT_NAMES.AggregatorOracle);
  const uniswapV3AdapterOracle = await get(
    CONTRACT_NAMES.UniswapV3AdapterOracle
  );

  let tx = await coreOracle.setRoutes(
    [
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.WBTC,
      ADDRESS.WETH,
      ADDRESS.ETH,
      ADDRESS.OHM,
      ADDRESS.ALCX,
      ADDRESS.wstETH,
      ADDRESS.BAL,
      ADDRESS.ICHI,
    ],
    [
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      aggregatorOracle.address,
      uniswapV3AdapterOracle.address,
    ]
  );
  await tx.wait(1);
};

export default deploy;
deploy.tags = ["CoreOracle"];
