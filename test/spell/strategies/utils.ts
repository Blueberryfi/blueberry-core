import { ethers, upgrades } from 'hardhat';
import { BigNumber, BigNumberish, utils } from 'ethers';
import {
  CoreOracle,
  ChainlinkAdapterOracle,
  UniswapV3AdapterOracle,
  WeightedBPTOracle,
  ProtocolConfig,
  SoftVault,
  HardVault,
  BErc20Delegator,
  BlueberryBank,
  ERC20,
  FeeManager,
  StableBPTOracle,
} from '../../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../../constant';
import { deployBTokens } from '../../helpers/money-market';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { faucetToken } from '../../helpers/paraswap';
import { deploySoftVaults } from '../../helpers/markets';

const OneDay = 86400;
// Use Two days time gap for chainlink, because we may increase timestamp manually to test reward amount
const TwoDays = OneDay * 2;
const OneHour = 3600;

export const setupOracles = async (): Promise<CoreOracle> => {
  const [admin] = await ethers.getSigners();

  const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
  const chainlinkAdapterOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(
    ChainlinkAdapterOracle,
    [admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );

  await chainlinkAdapterOracle.setTimeGap(
    [
      ADDRESS.ETH,
      ADDRESS.WETH,
      ADDRESS.DAI,
      ADDRESS.USDC,
      ADDRESS.BAL,
      ADDRESS.FRAX,
      ADDRESS.CRV,
      ADDRESS.LINK,
      ADDRESS.SUSHI,
      ADDRESS.CHAINLINK_BTC,
      ADDRESS.wstETH,
      ADDRESS.MIM,
      ADDRESS.WBTC,
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
      TwoDays,
    ]
  );

  await chainlinkAdapterOracle.setPriceFeeds(
    [
      ADDRESS.ETH,
      ADDRESS.WETH,
      ADDRESS.DAI,
      ADDRESS.USDC,
      ADDRESS.BAL,
      ADDRESS.FRAX,
      ADDRESS.CRV,
      ADDRESS.LINK,
      ADDRESS.WBTC,
      ADDRESS.wstETH,
      ADDRESS.MIM,
    ],
    [
      ADDRESS.CHAINLINK_ETH_USD_FEED,
      ADDRESS.CHAINLINK_ETH_USD_FEED,
      ADDRESS.CHAINLINK_DAI_USD_FEED,
      ADDRESS.CHAINLINK_USDC_USD_FEED,
      ADDRESS.CHAINLINK_BAL_USD_FEED,
      ADDRESS.CHAINLINK_FRAX_USD_FEED,
      ADDRESS.CHAINLINK_CRV_USD_FEED,
      ADDRESS.CHAINLINK_LINK_USD_FEED,
      ADDRESS.CHAINLINK_BTC_USD_FEED,
      ADDRESS.CHAINLINK_STETH_USD_FEED,
      ADDRESS.CHAINLINK_MIM_USD_FEED,
    ]
  );
  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  const oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });

  const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
  const LibInstance = await LinkedLibFactory.deploy();
  await LibInstance.deployed();

  const UniswapV3AdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV3AdapterOracle, {
    libraries: {
      UniV3WrappedLibContainer: LibInstance.address,
    },
  });
  const uniswapV3AdapterOracle = <UniswapV3AdapterOracle>await upgrades.deployProxy(
    UniswapV3AdapterOracle,
    [oracle.address, admin.address],
    {
      unsafeAllow: ['delegatecall', 'external-library-linking'],
    }
  );

  await uniswapV3AdapterOracle.setStablePools(
    [ADDRESS.OHM, ADDRESS.ICHI],
    [ADDRESS.UNI_V3_OHM_WETH, ADDRESS.UNI_V3_ICHI_USDC]
  );
  await uniswapV3AdapterOracle.setTimeGap([ADDRESS.OHM, ADDRESS.ICHI], [OneHour, OneHour]);

  await uniswapV3AdapterOracle.registerToken(ADDRESS.OHM);
  await uniswapV3AdapterOracle.registerToken(ADDRESS.ICHI);

  const WeightedBPTOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.WeightedBPTOracle);
  const weightedOracle = <WeightedBPTOracle>await upgrades.deployProxy(
    WeightedBPTOracleFactory,
    [ADDRESS.BALANCER_VAULT, oracle.address, admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );

  const StableBPTOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.StableBPTOracle);

  const stableOracle = <StableBPTOracle>await upgrades.deployProxy(
    StableBPTOracleFactory,
    [ADDRESS.BALANCER_VAULT, oracle.address, admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );

  await weightedOracle.connect(admin).setStablePoolOracle(stableOracle.address);
  await stableOracle.connect(admin).setWeightedPoolOracle(weightedOracle.address);

  await weightedOracle.connect(admin).registerBpt(ADDRESS.BAL_OHM_WETH);
  await stableOracle.connect(admin).registerBpt(ADDRESS.BAL_WSTETH_WETH);

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

export const getTokenAmountFromUSD = async (
  token: ERC20,
  oracle: CoreOracle,
  usdAmount: BigNumberish
): Promise<BigNumber> => {
  const price = await oracle.callStatic.getPrice(token.address);

  const decimals = await token.decimals();

  return utils
    .parseEther(usdAmount.toString())
    .mul(utils.parseEther('1'))
    .div(price)
    .div(utils.parseUnits('1', 18 - decimals));
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
  bank: BlueberryBank;
  oracle: CoreOracle;
  config: ProtocolConfig;
  feeManager: FeeManager;
  vaults: Vaults;
  admin: SignerWithAddress;
  alice: SignerWithAddress;
  treasury: SignerWithAddress;
};
