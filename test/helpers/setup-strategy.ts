import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import {
  BlueberryBank,
  CoreOracle,
  ERC20,
  FeeManager,
  IUniswapV2Router02,
  IWETH,
  MockOracle,
  ProtocolConfig,
} from '../../typechain-types';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, utils } from 'ethers';

export default class SetupStrategy {
  readonly ETH_PRICE = 1600;
  public tokens: { [key: string]: ERC20 | IWETH } = {};
  public accounts: { [key: string]: SignerWithAddress } = {};
  public bank: BlueberryBank | undefined;
  public mockOracle: MockOracle | undefined;
  public coreOracle: CoreOracle | undefined;
  public feeManager: FeeManager | undefined;
  public protocolConfig: ProtocolConfig | undefined;
  public uniswapRouter: IUniswapV2Router02 | undefined;
  public sushiswapRouter: IUniswapV2Router02 | undefined;

  constructor(wethAmount: number) {
    this.initAccounts();
    this.initTokens();
    this.initSwapRouters();
    this.accrueWeth(wethAmount);
    this.initMockOracleWithTokenPrice();
    this.initCoreOracleWithPriceRoutes();
    this.initBank();
  }

  private initAccounts(): SetupStrategy {
    (async () => {
      const [admin, alice, treasury] = await ethers.getSigners();
      this.accounts = {
        admin: admin,
        alice: alice,
        treasury: treasury,
      };
    })();

    return this;
  }

  private initTokens(): SetupStrategy {
    (async () => {
      this.tokens = {
        CRV: <ERC20>await ethers.getContractAt('ERC20', ADDRESS.CRV),
        BAL: <ERC20>await ethers.getContractAt('ERC20', ADDRESS.BAL),
        DAI: <ERC20>await ethers.getContractAt('ERC20', ADDRESS.DAI),
        FRAX: <ERC20>await ethers.getContractAt('ERC20', ADDRESS.FRAX),
        USDC: <ERC20>await ethers.getContractAt('ERC20', ADDRESS.USDC),
        USDT: <ERC20>await ethers.getContractAt('ERC20', ADDRESS.USDT),
        AURA: <ERC20>await ethers.getContractAt('ERC20', ADDRESS.AURA),
        WETH: <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, ADDRESS.WETH),
      };
    })();
    return this;
  }

  private initSwapRouters(): SetupStrategy {
    (async () => {
      this.uniswapRouter = await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER);
      this.sushiswapRouter = await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.SUSHI_ROUTER);
    })();

    return this;
  }

  private initMockOracleWithTokenPrice(): SetupStrategy {
    (async () => {
      this.mockOracle = await (await ethers.getContractFactory(CONTRACT_NAMES.MockOracle)).deploy();
      await this.mockOracle.deployed();

      await this.mockOracle.setPrice(
        [
          this.tokens.WETH.address,
          this.tokens.USDC.address,
          this.tokens.CRV.address,
          this.tokens.DAI.address,
          this.tokens.USDT.address,
          this.tokens.FRAX.address,
          this.tokens.AURA.address,
          this.tokens.BAL.address,
          ADDRESS.BAL_UDU,
        ],
        [
          BigNumber.from(10).pow(18).mul(this.ETH_PRICE),
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18), // $1
        ]
      );
    })();
    return this;
  }

  private initCoreOracleWithPriceRoutes(): SetupStrategy {
    (async () => {
      this.coreOracle = <CoreOracle>(
        await upgrades.deployProxy(
          await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle),
          [this.accounts.admin.address],
          { unsafeAllow: ['delegatecall'] }
        )
      );
      await this.coreOracle.deployed();

      const mockOracleAddress: string = this.mockOracle?.address || '';
      await this.coreOracle.setRoutes(
        [
          this.tokens.WETH.address,
          this.tokens.USDC.address,
          this.tokens.CRV.address,
          this.tokens.DAI.address,
          this.tokens.USDT.address,
          this.tokens.FRAX.address,
          this.tokens.AURA.address,
          this.tokens.BAL.address,
          ADDRESS.BAL_UDU,
        ],
        [
          mockOracleAddress,
          mockOracleAddress,
          mockOracleAddress,
          mockOracleAddress,
          mockOracleAddress,
          mockOracleAddress,
          mockOracleAddress,
          mockOracleAddress,
          mockOracleAddress,
        ]
      );
    })();
    return this;
  }

  private initBank() {
    (async () => {
      this.protocolConfig = <ProtocolConfig>await upgrades.deployProxy(
        await ethers.getContractFactory('ProtocolConfig'),
        [this.accounts.treasury.address, this.accounts.admin.address],
        {
          unsafeAllow: ['delegatecall'],
        }
      );
      await this.protocolConfig.deployed();

      this.feeManager = <FeeManager>await upgrades.deployProxy(
        await ethers.getContractFactory('FeeManager'),
        [this.protocolConfig.address, this.accounts.admin.address],
        {
          unsafeAllow: ['delegatecall'],
        }
      );
      await this.feeManager.deployed();
      await this.protocolConfig.setFeeManager(this.feeManager.address);

      this.bank = <BlueberryBank>await upgrades.deployProxy(
        await ethers.getContractFactory(CONTRACT_NAMES.BlueberryBank),
        [this.coreOracle?.address, this.protocolConfig.address, this.accounts.admin.address],
        {
          unsafeAllow: ['delegatecall'],
        }
      );
      await this.bank.deployed();
    })();
  }

  private accrueWeth(amount: number | 100): SetupStrategy {
    (async () => {
      await (this.tokens?.WETH as IWETH).deposit({ value: utils.parseUnits(amount.toString()) });
    })();
    return this;
  }

  public swapTokensWithUniswap(fromToken: string, toToken: string, amount: number): SetupStrategy {
    toToken = toToken.toUpperCase();
    fromToken = fromToken.toUpperCase();

    this._swapWith(this.uniswapRouter, ADDRESS.UNI_V2_ROUTER, { fromToken, toToken, amount });
    return this;
  }

  public swapTokensWithSushiswap(fromToken: string, toToken: string, amount: number): SetupStrategy {
    toToken = toToken.toUpperCase();
    fromToken = fromToken.toUpperCase();

    this._swapWith(this.sushiswapRouter, ADDRESS.SUSHI_ROUTER, { fromToken, toToken, amount });
    return this;
  }

  public setMockOracleTokenPrice(token: string, tokenPrice: number): SetupStrategy {
    if (!this.tokens[token]) {
      throw new Error(`${token} is not supported`);
    }

    (async () => {
      await this.mockOracle?.setPrice([this.tokens[token].address], [BigNumber.from(10).pow(18).mul(tokenPrice)]);
    })();
    return this;
  }

  public setCoreOraclePriceRoute(token: string): SetupStrategy {
    if (!this.tokens[token]) {
      throw new Error(`${token} is not supported`);
    }

    (async () => {
      const mockOracleAddress: string = this.mockOracle?.address || '';
      await this.coreOracle?.setRoutes([this.tokens[token].address], [mockOracleAddress]);
    })();
    return this;
  }

  private _swapWith(
    router: IUniswapV2Router02 | undefined,
    routerAddress: string,
    swapParams: {
      fromToken: string;
      toToken: string;
      amount: number;
    }
  ) {
    const { fromToken, toToken, amount } = swapParams;
    if (!this.tokens[fromToken] || !this.tokens[toToken]) {
      throw new Error(`${!fromToken ? fromToken : toToken} is not supported`);
    }

    (async () => {
      await this.tokens[fromToken].approve(routerAddress, ethers.constants.MaxUint256);
      await router?.swapExactTokensForTokens(
        utils.parseUnits(amount.toString()),
        0,
        [this.tokens[fromToken].address, this.tokens[toToken].address],
        this.accounts.admin.address,
        ethers.constants.MaxUint256
      );
    })();
  }
}
