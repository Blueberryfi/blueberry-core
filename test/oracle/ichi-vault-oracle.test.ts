import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import {
  ISwapRouter,
  MockOracle,
  CoreOracle,
  IchiVaultOracle,
  IICHIVault,
  ChainlinkAdapterOracle,
  IERC20Metadata,
  UniswapV3AdapterOracle,
  IWETH,
  IUniswapV2Router02,
  ERC20,
} from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;

describe('Ichi Vault Oracle', () => {
  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let mockOracle: MockOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;
  let ichiOracle: IchiVaultOracle;
  let ichiVault: IICHIVault;
  let uniswapV3Oracle: UniswapV3AdapterOracle;
  let swapRouter: ISwapRouter;

  let weth: IWETH;
  let usdc: ERC20;

  before(async () => {
    [admin, user] = await ethers.getSigners();

    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);

    const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
    mockOracle = <MockOracle>await MockOracle.deploy();
    await mockOracle.deployed();

    const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>(
      await upgrades.deployProxy(CoreOracleFactory, [admin.address], { unsafeAllow: ['delegatecall'] })
    );

    await coreOracle.deployed();

    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkAdapterOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(
      ChainlinkAdapterOracle,
      [admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await chainlinkAdapterOracle.deployed();
    await chainlinkAdapterOracle.setTimeGap([USDC], [86400]);
    await chainlinkAdapterOracle.setPriceFeeds([USDC], [ADDRESS.CHAINLINK_USDC_USD_FEED]);

    ichiVault = <IICHIVault>await ethers.getContractAt(CONTRACT_NAMES.IICHIVault, ADDRESS.ICHI_VAULT_USDC);

    const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
    const LibInstance = await LinkedLibFactory.deploy();
    const UniswapV3AdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV3AdapterOracle, {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    });
    uniswapV3Oracle = <UniswapV3AdapterOracle>await upgrades.deployProxy(
      UniswapV3AdapterOracle,
      [coreOracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall', 'external-library-linking'],
      }
    );
    await uniswapV3Oracle.deployed();
    await uniswapV3Oracle.setStablePools([ICHI], [ADDRESS.UNI_V3_ICHI_USDC]);
    await uniswapV3Oracle.setTimeGap(
      [ICHI],
      [3600] // timeAgo - 10 s
    );

    await coreOracle.setRoutes([USDC, ICHI], [chainlinkAdapterOracle.address, uniswapV3Oracle.address]);

    const IchiVaultOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultOracle, {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    });
    ichiOracle = <IchiVaultOracle>await upgrades.deployProxy(IchiVaultOracle, [coreOracle.address, admin.address], {
      unsafeAllow: ['delegatecall', 'external-library-linking'],
    });
    await ichiOracle.deployed();

    swapRouter = <ISwapRouter>await ethers.getContractAt('ISwapRouter', ADDRESS.UNI_V3_ROUTER);

    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
    await weth.deposit({ value: utils.parseUnits('20') });

    // swap 40 weth -> usdc
    await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
    const uniV2Router = <IUniswapV2Router02>(
      await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER)
    );
    await uniV2Router.swapExactTokensForTokens(
      utils.parseUnits('20'),
      0,
      [WETH, USDC],
      admin.address,
      ethers.constants.MaxUint256
    );
  });

  describe('Owner', () => {
    it('should be able to set price deviation', async () => {
      await expect(ichiOracle.connect(user).setPriceDeviation(ICHI, 200)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );

      await expect(ichiOracle.setPriceDeviation(ICHI, 1200))
        .to.be.revertedWithCustomError(ichiOracle, 'OUT_OF_DEVIATION_CAP')
        .withArgs(1200);

      await expect(ichiOracle.setPriceDeviation(ethers.constants.AddressZero, 600)).to.be.revertedWithCustomError(
        ichiOracle,
        'ZERO_ADDRESS'
      );

      await expect(ichiOracle.setPriceDeviation(ICHI, 300))
        .to.be.emit(ichiOracle, 'SetPriceDeviation')
        .withArgs(ICHI, 300);
    });

    it('should be able to register new vault', async () => {
      await expect(ichiOracle.connect(user).registerVault(ADDRESS.ICHI_VAULT_USDC)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );

      await expect(ichiOracle.connect(admin).registerVault(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
        ichiOracle,
        'ZERO_ADDRESS'
      );
      await uniswapV3Oracle.registerToken(ICHI);
      await expect(ichiOracle.connect(admin).registerVault(ADDRESS.ICHI_VAULT_USDC))
        .to.be.emit(ichiOracle, 'RegisterLpToken')
        .withArgs(ADDRESS.ICHI_VAULT_USDC);
    });
  });

  it('should revert price feed for empty vault', async () => {
    const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
    const LibInstance = await LinkedLibFactory.deploy();

    const IchiVault = await ethers.getContractFactory('MockIchiVault', {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    });
    const newVault = await IchiVault.deploy(ADDRESS.UNI_V3_ICHI_USDC, true, true, admin.address, admin.address, 3600);
    await ichiOracle.connect(admin).registerVault(newVault.address);

    const price = await ichiOracle.callStatic.getPrice(newVault.address);
    expect(price).to.be.equal(0);
  });

  it('should revert price feed for pools have too short twap period', async () => {
    const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
    const LibInstance = await LinkedLibFactory.deploy();

    const IchiVault = await ethers.getContractFactory('MockIchiVault', {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    });
    const newVault = await IchiVault.deploy(
      ADDRESS.UNI_V3_ICHI_USDC,
      true,
      true,
      admin.address,
      admin.address,
      60 // 60 seconds
    );

    await ichiOracle.connect(admin).registerVault(newVault.address);

    await usdc.approve(newVault.address, ethers.constants.MaxUint256);
    await newVault.deposit(0, utils.parseUnits('100', 6), admin.address);

    await expect(ichiOracle.callStatic.getPrice(newVault.address))
      .to.be.revertedWithCustomError(ichiOracle, 'TOO_LOW_MEAN')
      .withArgs(60);
  });

  it('should revert price feed for pools have too long twap period', async () => {
    const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
    const LibInstance = await LinkedLibFactory.deploy();

    const IchiVault = await ethers.getContractFactory('MockIchiVault', {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    });
    const newVault = await IchiVault.deploy(
      ADDRESS.UNI_V3_ICHI_USDC,
      true,
      true,
      admin.address,
      admin.address,
      60 * 60 * 24 * 3 // 3 days
    );
    await usdc.approve(newVault.address, ethers.constants.MaxUint256);
    await newVault.deposit(0, utils.parseUnits('100', 6), admin.address);

    await ichiOracle.connect(admin).registerVault(newVault.address);

    await expect(ichiOracle.callStatic.getPrice(newVault.address))
      .to.be.revertedWithCustomError(ichiOracle, 'TOO_LONG_DELAY')
      .withArgs(60 * 60 * 24 * 3);
  });

  it('USDC/ICHI Angel Vault Price', async () => {
    await uniswapV3Oracle.registerToken(ICHI);
    const ichiPrice = await uniswapV3Oracle.callStatic.getPrice(ICHI);
    console.log('ICHI Price', utils.formatUnits(ichiPrice));
    await ichiOracle.connect(admin).registerVault(ADDRESS.ICHI_VAULT_USDC);
    const lpPrice = await ichiOracle.callStatic.getPrice(ADDRESS.ICHI_VAULT_USDC);
    console.log('USDC/ICHI Vault Price: \t', utils.formatUnits(lpPrice, 18));

    // calculate lp price manually.
    const reserveData = await ichiVault.getTotalAmounts();
    const token0 = await ichiVault.token0();
    const token1 = await ichiVault.token1();
    const totalSupply = await ichiVault.totalSupply();
    const usdcPrice = await coreOracle.callStatic.getPrice(ADDRESS.USDC);
    const token0Contract = <IERC20Metadata>await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token0);
    const token1Contract = <IERC20Metadata>await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token1);
    const token0Decimal = await token0Contract.decimals();
    const token1Decimal = await token1Contract.decimals();

    const reserve1 = BigNumber.from(reserveData[0].mul(ichiPrice).div(BigNumber.from(10).pow(token0Decimal)));
    const reserve2 = BigNumber.from(reserveData[1].mul(usdcPrice).div(BigNumber.from(10).pow(token1Decimal)));
    const lpPriceM = reserve1.add(reserve2).mul(BigNumber.from(10).pow(18)).div(totalSupply);

    console.log('Manual Price:\t\t', utils.formatUnits(lpPriceM));

    expect(lpPrice.eq(lpPriceM)).to.be.true;
  });

  describe('Flashloan attack test', () => {
    it('Vault Reserve manipulation', async () => {
      // Prepare USDC
      // deposit 80 eth -> 80 WETH
      usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
      weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
      await weth.deposit({ value: utils.parseUnits('900') });

      // swap 40 weth -> usdc
      await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
      const uniV2Router = <IUniswapV2Router02>(
        await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER)
      );
      await uniV2Router.swapExactTokensForTokens(
        utils.parseUnits('900'),
        0,
        [WETH, USDC],
        admin.address,
        ethers.constants.MaxUint256
      );
      console.log('USDC Balance: ', utils.formatUnits(await usdc.balanceOf(admin.address), 6));
      console.log('\n=== Before ===');
      await uniswapV3Oracle.registerToken(ICHI);
      const ichiPrice = await uniswapV3Oracle.callStatic.getPrice(ICHI);
      console.log('ICHI Price', utils.formatUnits(ichiPrice));

      let lpPrice = await ichiOracle.callStatic.getPrice(ADDRESS.ICHI_VAULT_USDC);
      console.log('USDC/ICHI Lp Price: \t', utils.formatUnits(lpPrice, 18));

      console.log('\n=== Deposit $1,000 USDC on the ICHI Vault ===');
      await usdc.approve(ichiVault.address, ethers.constants.MaxUint256);
      await ichiVault.deposit(0, utils.parseUnits('1000', 6), admin.address);
      lpPrice = await ichiOracle.callStatic.getPrice(ADDRESS.ICHI_VAULT_USDC);
      console.log('USDC/ICHI Lp Price: \t', utils.formatUnits(lpPrice, 18));

      console.log('\n=== Deposit $1,000,000 USDC on the ICHI Vault ===');
      await ichiVault.deposit(0, utils.parseUnits('1000000', 6), admin.address);
      lpPrice = await ichiOracle.callStatic.getPrice(ADDRESS.ICHI_VAULT_USDC);
      console.log('USDC/ICHI Lp Price: \t', utils.formatUnits(lpPrice, 18));
    });

    it('Swap tokens on Uni V3 Pool to manipulate pool reserves', async () => {
      // Prepare USDC
      // deposit 900 eth -> 900 WETH
      usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
      weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
      await weth.deposit({ value: utils.parseUnits('900') });

      // swap 40 weth -> usdc
      await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
      const uniV2Router = <IUniswapV2Router02>(
        await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER)
      );
      await uniV2Router.swapExactTokensForTokens(
        utils.parseUnits('900'),
        0,
        [WETH, USDC],
        admin.address,
        ethers.constants.MaxUint256
      );
      console.log('USDC Balance: ', utils.formatUnits(await usdc.balanceOf(admin.address), 6));

      console.log('\n=== Before ===');
      const ichiPrice = await uniswapV3Oracle.callStatic.getPrice(ICHI);
      console.log('ICHI Price', utils.formatUnits(ichiPrice));

      const lpPrice = await ichiOracle.callStatic.getPrice(ADDRESS.ICHI_VAULT_USDC);
      console.log('USDC/ICHI Lp Price: \t', utils.formatUnits(lpPrice, 18));

      // Swap $1K USDC to ICHI on Uni V3
      console.log('=== Swap $1K USDC to ICHI ===');
      await usdc.approve(ADDRESS.UNI_V3_ROUTER, ethers.constants.MaxUint256);
      await swapRouter.exactInputSingle({
        tokenIn: USDC,
        tokenOut: ICHI,
        fee: 10000,
        recipient: admin.address,
        deadline: Math.ceil(new Date().getTime() / 1000),
        amountIn: utils.parseUnits('1000', 6),
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0,
      });

      // Swap $10K USDC to ICHI on Uni V3
      console.log('=== Swap $10K USDC to ICHI (Reverted) ===');
      console.log('Price Deviation Config:', await ichiOracle.getMaxPriceDeviation(ICHI));
      await swapRouter.exactInputSingle({
        tokenIn: USDC,
        tokenOut: ICHI,
        fee: 10000,
        recipient: admin.address,
        deadline: Math.ceil(new Date().getTime() / 1000),
        amountIn: utils.parseUnits('10000', 6),
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0,
      });
      await expect(ichiOracle.callStatic.getPrice(ADDRESS.ICHI_VAULT_USDC)).to.be.revertedWithCustomError(
        ichiOracle,
        'EXCEED_DEVIATION'
      );
    });
  });
});
