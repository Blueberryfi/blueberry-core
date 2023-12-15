import { ethers, upgrades } from "hardhat";
import { BigNumber, BigNumberish, utils } from "ethers";
import {
  CoreOracle,
  ChainlinkAdapterOracle,
  UniswapV3AdapterOracle,
  WeightedBPTOracle,
  ProtocolConfig,
  SoftVault,
  HardVault,
  BErc20Delegator,
  BlueBerryBank,
  ERC20,
  FeeManager,
} from "../../../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../../../constant";
import { deployBTokens } from "../../helpers/money-market";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { faucetToken } from "../../helpers/paraswap";
import { setTokenBalance } from "../../helpers";

const OneDay = 86400;
// Use Two days time gap for chainlink, because we may increase timestamp manually to test reward amount
const TwoDays = OneDay * 2;
const OneHour = 3600;

export const setupOracles = async (): Promise<CoreOracle> => {
  console.log("setup oracles");
  const ChainlinkAdapterOracle = await ethers.getContractFactory(
    CONTRACT_NAMES.ChainlinkAdapterOracle
  );
  const chainlinkAdapterOracle = <ChainlinkAdapterOracle>(
    await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry)
  );

  await chainlinkAdapterOracle.setTokenRemappings(
    [ADDRESS.WETH, ADDRESS.WBTC, ADDRESS.wstETH],
    [ADDRESS.ETH, ADDRESS.CHAINLINK_BTC, ADDRESS.stETH]
  );
  console.log("remappings set");
  await chainlinkAdapterOracle.setTimeGap(
    [
      ADDRESS.ETH,
      ADDRESS.DAI,
      ADDRESS.USDC,
      ADDRESS.DAI,
      ADDRESS.BAL,
      ADDRESS.FRAX,
      ADDRESS.CRV,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.SUSHI,
      ADDRESS.CHAINLINK_BTC,
      ADDRESS.stETH,
    ],
    [
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
      TwoDays,
    ]
  );

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  const oracle = <CoreOracle>(
    await upgrades.deployProxy(CoreOracle, { unsafeAllow: ["delegatecall"] })
  );

  const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
  const LibInstance = await LinkedLibFactory.deploy();
  await LibInstance.deployed();

  const UniswapV3AdapterOracle = await ethers.getContractFactory(
    CONTRACT_NAMES.UniswapV3AdapterOracle,
    {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    }
  );
  const uniswapV3AdapterOracle = <UniswapV3AdapterOracle>(
    await UniswapV3AdapterOracle.deploy(oracle.address)
  );

  await uniswapV3AdapterOracle.setStablePools(
    [ADDRESS.OHM, ADDRESS.ICHI],
    [ADDRESS.UNI_V3_OHM_WETH, ADDRESS.UNI_V3_ICHI_USDC]
  );
  await uniswapV3AdapterOracle.setTimeGap(
    [ADDRESS.OHM, ADDRESS.ICHI],
    [OneHour, OneHour]
  );

  const WeightedBPTOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.WeightedBPTOracle
  );
  const weightedOracle = <WeightedBPTOracle>(
    await WeightedBPTOracleFactory.deploy(oracle.address)
  );

  const StableBPTOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.StableBPTOracle
  );

  const stableOracle = <WeightedBPTOracle>(
    await StableBPTOracleFactory.deploy(oracle.address)
  );

  await oracle.setRoutes(
    [
      ADDRESS.USDC,
      ADDRESS.ICHI,
      ADDRESS.CRV,
      ADDRESS.DAI,
      ADDRESS.MIM,
      ADDRESS.LINK,
      ADDRESS.OHM,
      ADDRESS.SUSHI,
      ADDRESS.BAL,
      ADDRESS.WETH,
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.USDT,
      ADDRESS.FRAX,
      ADDRESS.BAL_OHM_WETH,
      ADDRESS.BAL_WSTETH_WETH,
    ],
    [
      chainlinkAdapterOracle.address,
      uniswapV3AdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      uniswapV3AdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      chainlinkAdapterOracle.address,
      weightedOracle.address,
      stableOracle.address,
    ]
  );

  return oracle;
};

export const setupVaults = async (
  bank: BlueBerryBank,
  oracle: CoreOracle,
  config: ProtocolConfig,
  signer: SignerWithAddress
): Promise<Vaults> => {
  let bTokens = await deployBTokens(signer.address, oracle.address);

  const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
  const hardVault = <HardVault>await upgrades.deployProxy(
    HardVault,
    [config.address],
    {
      unsafeAllow: ["delegatecall"],
    }
  );

  const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);

  const softVaults: SoftVault[] = [];
  const bTokenList: BErc20Delegator[] = [];
  const tokens: ERC20[] = [];

  for (let key of Object.keys(bTokens)) {
    if (key === "comptroller") continue;
    if (key === "extraBTokens") continue;
    const bToken = (bTokens as any)[key] as any as BErc20Delegator;
    const softVault = <SoftVault>(
      await upgrades.deployProxy(
        SoftVault,
        [
          config.address,
          bToken.address,
          `Interest Bearing ${(await bToken.name()).split(" ")[1]}`,
          `i${await bToken.symbol()}`,
        ],
        { unsafeAllow: ["delegatecall"] }
      )
    );

    softVaults.push(softVault);
    bTokenList.push(bToken);

    await bTokens.comptroller._setCreditLimit(
      bank.address,
      bToken.address,
      utils.parseEther("3000000")
    );

    const underlyingToken = <ERC20>(
      await ethers.getContractAt("ERC20", await bToken.underlying())
    );
    tokens.push(underlyingToken);

    const amount = await faucetToken(
      underlyingToken.address,
      utils.parseEther("20"),
      signer,
      100
    );
    await underlyingToken
      .connect(signer)
      .approve(softVault.address, ethers.constants.MaxUint256);

    await softVault.connect(signer).deposit(amount);
  }
  return {
    hardVault,
    softVaults,
    bTokens: bTokenList,
    tokens,
  };
};

export const setupBasicBank = async (): Promise<Protocol> => {
  const [admin, alice, treasury] = await ethers.getSigners();

  const Config = await ethers.getContractFactory("ProtocolConfig");
  const config = <ProtocolConfig>await upgrades.deployProxy(
    Config,
    [treasury.address],
    {
      unsafeAllow: ["delegatecall"],
    }
  );

  const FeeManager = await ethers.getContractFactory("FeeManager");
  const feeManager = <FeeManager>await upgrades.deployProxy(
    FeeManager,
    [config.address],
    {
      unsafeAllow: ["delegatecall"],
    }
  );
  await config.setFeeManager(feeManager.address);

  const oracle = await setupOracles();

  const BlueBerryBank = await ethers.getContractFactory(
    CONTRACT_NAMES.BlueBerryBank
  );

  const bank = <BlueBerryBank>(
    await upgrades.deployProxy(
      BlueBerryBank,
      [oracle.address, config.address],
      { unsafeAllow: ["delegatecall"] }
    )
  );

  const vaults = await setupVaults(bank, oracle, config, admin);

  await bank.whitelistTokens(
    vaults.tokens.map((token) => token.address),
    vaults.tokens.map(() => true)
  );

  for (let i = 0; i < vaults.softVaults.length; i += 1) {
    const softVault = vaults.softVaults[i];

    await bank.addBank(
      vaults.tokens[i].address,
      softVault.address,
      vaults.hardVault.address,
      8500
    );

  }

  return {
    bank,
    oracle,
    config,
    feeManager,
    vaults,
    admin,
    alice,
    treasury,
  };
};

export const getTokenAmountFromUSD = async (
  token: ERC20,
  oracle: CoreOracle,
  usdAmount: BigNumberish
): Promise<BigNumber> => {
  console.log("Enter");
  const price = await oracle.callStatic.getPrice(token.address);
  console.log("Price", price.toString());
  const decimals = await token.decimals();

  return utils
    .parseEther(usdAmount.toString())
    .mul(utils.parseEther("1"))
    .div(price)
    .div(utils.parseUnits("1", 18 - decimals));
};

export type StrategyInfo = {
  type: string;
  address: string;
  poolId?: number;
  borrowAssets: string[];
  collateralAssets: string[];
  maxLtv: number;
  maxStrategyBorrow: number;
};

export type Vaults = {
  hardVault: HardVault;
  softVaults: SoftVault[];
  bTokens: BErc20Delegator[];
  tokens: ERC20[];
};

export type Protocol = {
  bank: BlueBerryBank;
  oracle: CoreOracle;
  config: ProtocolConfig;
  feeManager: FeeManager;
  vaults: Vaults;
  admin: SignerWithAddress;
  alice: SignerWithAddress;
  treasury: SignerWithAddress;
};