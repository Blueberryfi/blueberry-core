import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, constants, utils, Contract } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
  BlueberryBank,
  CoreOracle,
  IchiSpell,
  SoftVault,
  MockOracle,
  WERC20,
  WIchiFarm,
  ProtocolConfig,
  MockIchiVault,
  ERC20,
  MockIchiV2,
  MockIchiFarm,
  HardVault,
} from '../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../constant';
import SpellABI from '../abi/contracts/spell/IchiSpell.sol/IchiSpell.json';

import { near } from './assertions/near';
import { roughlyNear } from './assertions/roughlyNear';
import { Protocol, setupIchiProtocol } from './helpers/setup-ichi-protocol';
import { evm_mine_blocks, evm_increaseTime, fork } from './helpers';
import { TickMath } from '@uniswap/v3-sdk';

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId

describe('Bank', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let usdc: ERC20;
  let ichi: MockIchiV2;
  let ichiV1: ERC20;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let oracle: CoreOracle;
  let spell: IchiSpell;
  let wichi: WIchiFarm;
  let bank: BlueberryBank;
  let config: ProtocolConfig;
  let usdcSoftVault: SoftVault;
  let ichiSoftVault: SoftVault;
  let wethSoftVault: SoftVault;
  let hardVault: HardVault;
  let ichiFarm: MockIchiFarm;
  let ichiVault: MockIchiVault;
  let protocol: Protocol;
  let bCRV: Contract;

  before(async () => {
    await fork();

    [admin, alice] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    ichi = <MockIchiV2>await ethers.getContractAt('MockIchiV2', ICHI);
    ichiV1 = <ERC20>await ethers.getContractAt('ERC20', ICHIV1);

    protocol = await setupIchiProtocol();
    config = protocol.config;
    bank = protocol.bank;
    spell = protocol.ichiSpell;
    ichiFarm = protocol.ichiFarm;
    ichiVault = protocol.ichi_USDC_ICHI_Vault;
    wichi = protocol.wichi;
    werc20 = protocol.werc20;
    oracle = protocol.oracle;
    mockOracle = protocol.mockOracle;
    usdcSoftVault = protocol.usdcSoftVault;
    ichiSoftVault = protocol.ichiSoftVault;
    wethSoftVault = protocol.wethSoftVault;
    hardVault = protocol.hardVault;
    bCRV = protocol.bCRV;
  });

  beforeEach(async () => {});

  describe('Constructor', () => {
    it('should revert Bank deployment when invalid args provided', async () => {
      const BlueberryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueberryBank);
      await expect(
        upgrades.deployProxy(BlueberryBank, [ethers.constants.AddressZero, config.address, admin.address], {
          unsafeAllow: ['delegatecall'],
        })
      ).to.be.revertedWithCustomError(BlueberryBank, 'ZERO_ADDRESS');

      await expect(
        upgrades.deployProxy(BlueberryBank, [oracle.address, ethers.constants.AddressZero, admin.address], {
          unsafeAllow: ['delegatecall'],
        })
      ).to.be.revertedWithCustomError(BlueberryBank, 'ZERO_ADDRESS');
    });
    it('should initialize states on constructor', async () => {
      const BlueberryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueberryBank);
      const bank = <BlueberryBank>await upgrades.deployProxy(
        BlueberryBank,
        [oracle.address, config.address, admin.address],
        {
          unsafeAllow: ['delegatecall'],
        }
      );
      await bank.deployed();

      expect(await bank.POSITION_ID()).to.be.equal(ethers.constants.MaxUint256);
      expect(await bank.SPELL()).to.be.equal('0x0000000000000000000000000000000000000001');
      expect(await bank.getOracle()).to.be.equal(oracle.address);
      expect(await bank.getConfig()).to.be.equal(config.address);
      expect(await bank.getNextPositionId()).to.be.equal(1);
      expect(await bank.getBankStatus()).to.be.equal(15);
    });
    it('should revert initializing twice', async () => {
      await expect(bank.initialize(oracle.address, config.address, admin.address)).to.be.revertedWith(
        'Initializable: contract is already initialized'
      );
    });
  });

  describe('Execution', () => {
    const depositAmount = utils.parseUnits('10', 18); // worth of $400
    const borrowAmount = utils.parseUnits('30', 6);
    const iface = new ethers.utils.Interface(SpellABI);
    before(async () => {
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(18).mul(5), // $5
        ]
      );
    });
    it('should revert execution to not whitelisted spells', async () => {
      await expect(
        bank.execute(
          0,
          ethers.constants.AddressZero,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      ).to.be.revertedWithCustomError(bank, 'SPELL_NOT_WHITELISTED');
    });
    it('should revert execution for existing position when given position id is greater than last pos id', async () => {
      const positionId = await bank.getNextPositionId();
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'BAD_POSITION')
        .withArgs(positionId);
    });
    it('should revert execution for existing position from non-position owner', async () => {
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPositionFarm', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );

      const positionId = await bank.getNextPositionId();
      await expect(
        bank.connect(alice).execute(
          positionId.sub(1),
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'NOT_FROM_OWNER')
        .withArgs(positionId.sub(1), alice.address);
    });
    it('should revert execution for not-whitelisted underlying token lending', async () => {
      await bank.whitelistTokens([ICHI], [false]);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'TOKEN_NOT_WHITELISTED')
        .withArgs(ICHI);
      await bank.whitelistTokens([ICHI], [true]);
    });
    it('should revert opening execution with non whitelisted debt token', async () => {
      await bank.whitelistTokens([USDC], [false]);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'TOKEN_NOT_WHITELISTED')
        .withArgs(USDC);
      await bank.whitelistTokens([USDC], [true]);
    });
    it('should revert opening execution for existing position with different debt token', async () => {
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPositionFarm', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );

      const positionId = await bank.getNextPositionId();
      await expect(
        bank.execute(
          positionId.sub(1),
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: DAI,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'INCORRECT_DEBT')
        .withArgs(DAI);
    });
    it('should revert opening execution for existing position with different isolated token', async () => {
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPositionFarm', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );

      const positionId = await bank.getNextPositionId();
      await expect(
        bank.execute(
          positionId.sub(1),
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: DAI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'INCORRECT_UNDERLYING')
        .withArgs(DAI);
    });
    it('should revert opening execution for existing position with different wrapper token', async () => {
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPositionFarm', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );

      const positionId = await bank.getNextPositionId();
      const position = await bank.getPositionInfo(positionId.sub(1));
      await expect(
        bank.execute(
          positionId.sub(1),
          spell.address,
          iface.encodeFunctionData('openPosition', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'DIFF_COL_EXIST')
        .withArgs(position.collToken);
    });
    it('should revert direct call to lending, withdrawLend, borrow, repay, putCollateral', async () => {
      await expect(bank.lend(USDC, depositAmount)).to.be.revertedWithCustomError(bank, 'NOT_IN_EXEC');
      await expect(bank.withdrawLend(USDC, depositAmount)).to.be.revertedWithCustomError(bank, 'NOT_IN_EXEC');
      await expect(bank.borrow(USDC, depositAmount)).to.be.revertedWithCustomError(bank, 'NOT_IN_EXEC');
      await expect(bank.repay(USDC, depositAmount)).to.be.revertedWithCustomError(bank, 'NOT_IN_EXEC');
      await expect(bank.putCollateral(USDC, 0, depositAmount)).to.be.revertedWithCustomError(bank, 'NOT_IN_EXEC');
      await expect(bank.takeCollateral(0)).to.be.revertedWithCustomError(bank, 'NOT_IN_EXEC');
    });
    it('should revert execution for not whitelisted wrapper', async () => {
      await bank.whitelistERC1155([wichi.address], false);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'TOKEN_NOT_WHITELISTED')
        .withArgs(wichi.address);
      await bank.whitelistERC1155([wichi.address], true);
    });
    it('should revert close execution for existing position with different isolated token', async () => {
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(16).mul(326), // $3.26
        ]
      );
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );

      const positionId = (await bank.getNextPositionId()).sub(1);
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('closePosition', [
            {
              strategyId: 0,
              collToken: DAI,
              borrowToken: USDC,
              amountRepay: ethers.constants.MaxUint256,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: 1,
              amountToSwap: 0,
              swapData: '0x',
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'INVALID_UTOKEN')
        .withArgs(DAI);
    });
    it('should revert close execution for existing position with different debt token', async () => {
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );

      const positionId = (await bank.getNextPositionId()).sub(1);
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(16).mul(350), // $3.5
        ]
      );

      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('closePosition', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: ICHI,
              amountRepay: ethers.constants.MaxUint256,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: 1,
              amountToSwap: 0,
              swapData: '0x',
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'INCORRECT_DEBT')
        .withArgs(ICHI);
    });
    it('should revert close execution for for not whitelisted debt token', async () => {
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(16).mul(326), // $3.26
        ]
      );
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );

      await bank.whitelistTokens([USDC], [false]);
      const positionId = (await bank.getNextPositionId()).sub(1);
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('closePosition', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              amountRepay: ethers.constants.MaxUint256,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: 1,
              amountToSwap: 0,
              swapData: '0x',
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(bank, 'TOKEN_NOT_WHITELISTED')
        .withArgs(USDC);
      await bank.whitelistTokens([USDC], [true]);
    });
    it('should be able to increase position by putting more coll, debt', async () => {
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );
      const positionId = (await bank.getNextPositionId()).sub(1);
      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );
    });
  });
  describe('Liquidation', () => {
    const depositAmount = utils.parseUnits('100', 18); // worth of $400
    const borrowAmount = utils.parseUnits('300', 6);
    const iface = new ethers.utils.Interface(SpellABI);
    let positionId: BigNumber;

    beforeEach(async () => {
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(18).mul(5), // $5
        ]
      );
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPositionFarm', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: ICHI_VAULT_PID,
          },
        ])
      );
      positionId = (await bank.getNextPositionId()).sub(1);
    });
    it('should revert liquidation when repay is not allowed', async () => {
      const liqAmount = utils.parseUnits('100', 6);
      await bank.setBankStatus(13);
      await expect(bank.connect(alice).liquidate(1, USDC, liqAmount)).to.be.revertedWithCustomError(
        bank,
        'REPAY_NOT_ALLOWED'
      );
      await bank.setBankStatus(15);
    });
    it('should revert liquidation when zero amount given', async () => {
      await expect(bank.connect(alice).liquidate(1, USDC, 0)).to.be.revertedWithCustomError(bank, 'ZERO_AMOUNT');
    });
    it('should revert liquidation when the pos is not liquidatable', async () => {
      const liqAmount = utils.parseUnits('100', 6);
      expect(await bank.callStatic.isLiquidatable(1)).to.be.false;
      await expect(bank.connect(alice).liquidate(1, USDC, liqAmount))
        .to.be.revertedWithCustomError(bank, 'NOT_LIQUIDATABLE')
        .withArgs(1);
    });
    it('should revert when repayAllowed is not warmed up', async () => {
      await evm_mine_blocks(10);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      let positionInfo = await bank.getPositionInfo(positionId);
      let debtValue = await bank.callStatic.getDebtValue(positionId);
      let positionValue = await bank.callStatic.getPositionValue(positionId);
      let risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Debt Value:', utils.formatUnits(debtValue));
      console.log('Position Value:', utils.formatUnits(positionValue));
      console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
      console.log('Position Size:', utils.formatUnits(positionInfo.collateralSize));

      const pendingIchi = await ichiFarm.pendingIchi(ICHI_VAULT_PID, wichi.address);
      console.log('Pending ICHI:', utils.formatUnits(pendingIchi, 9));
      await ichiV1.transfer(ichiFarm.address, pendingIchi.mul(100));
      await ichiFarm.updatePool(ICHI_VAULT_PID);

      console.log('===ICHI token dumped from $5 to $0.1===');
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(17).mul(5), // $0.5
        ]
      );
      positionInfo = await bank.getPositionInfo(positionId);
      debtValue = await bank.callStatic.getDebtValue(positionId);
      positionValue = await bank.callStatic.getPositionValue(positionId);
      risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Cur Pos:', positionInfo);
      console.log('Debt Value:', utils.formatUnits(debtValue));
      console.log('Position Value:', utils.formatUnits(positionValue));
      console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
      console.log('Position Size:', utils.formatUnits(positionInfo.collateralSize));

      console.log('Is Liquidatable:', await bank.callStatic.isLiquidatable(positionId));
      expect(await bank.callStatic.isLiquidatable(positionId)).to.be.true;

      console.log('===Portion Liquidated===');
      const liqAmount = utils.parseUnits('100', 6);
      await usdc.connect(alice).approve(bank.address, liqAmount);
      await expect(bank.connect(alice).liquidate(positionId, USDC, liqAmount)).to.be.revertedWithCustomError(
        bank,
        'REPAY_ALLOW_NOT_WARMED_UP'
      );
    });
    it('should be able to liquidate the position when repayAllowed is warmed up => (OV - PV)/CV = LT', async () => {
      await evm_increaseTime(4 * 3600);
      await evm_mine_blocks(10);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      let positionInfo = await bank.getPositionInfo(positionId);
      let debtValue = await bank.callStatic.getDebtValue(positionId);
      let positionValue = await bank.callStatic.getPositionValue(positionId);
      let risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Debt Value:', utils.formatUnits(debtValue));
      console.log('Position Value:', utils.formatUnits(positionValue));
      console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
      console.log('Position Size:', utils.formatUnits(positionInfo.collateralSize));

      const pendingIchi = await ichiFarm.pendingIchi(ICHI_VAULT_PID, wichi.address);
      console.log('Pending ICHI:', utils.formatUnits(pendingIchi, 9));
      await ichiV1.transfer(ichiFarm.address, pendingIchi.mul(100));
      await ichiFarm.updatePool(ICHI_VAULT_PID);

      console.log('===ICHI token dumped from $5 to $0.1===');
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(17).mul(5), // $0.5
        ]
      );
      positionInfo = await bank.getPositionInfo(positionId);
      debtValue = await bank.callStatic.getDebtValue(positionId);
      positionValue = await bank.callStatic.getPositionValue(positionId);
      risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Cur Pos:', positionInfo);
      console.log('Debt Value:', utils.formatUnits(debtValue));
      console.log('Position Value:', utils.formatUnits(positionValue));
      console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
      console.log('Position Size:', utils.formatUnits(positionInfo.collateralSize));

      expect(await bank.callStatic.isLiquidatable(positionId)).to.be.true;
      console.log('Is Liquidatable:', await bank.callStatic.isLiquidatable(positionId));

      console.log('===Portion Liquidated===');
      const liqAmount = utils.parseUnits('100', 6);
      await usdc.connect(alice).approve(bank.address, liqAmount);
      await expect(bank.connect(alice).liquidate(positionId, USDC, liqAmount)).to.be.emit(bank, 'Liquidate');

      positionInfo = await bank.getPositionInfo(positionId);
      debtValue = await bank.callStatic.getDebtValue(positionId);
      positionValue = await bank.callStatic.getPositionValue(positionId);
      risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Cur Pos:', positionInfo);
      console.log('Debt Value:', utils.formatUnits(debtValue));
      console.log('Position Value:', utils.formatUnits(positionValue));
      console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
      console.log('Position Size:', utils.formatUnits(positionInfo.collateralSize));

      const colToken = await ethers.getContractAt('ERC1155Upgradeable', positionInfo.collToken);
      const uVToken = await ethers.getContractAt('ERC20Upgradeable', ichiSoftVault.address);
      console.log(
        "Liquidator's Position Balance:",
        utils.formatUnits(await colToken.balanceOf(alice.address, positionInfo.collId))
      );
      console.log("Liquidator's Collateral Balance:", utils.formatUnits(await uVToken.balanceOf(alice.address)));

      console.log('===Full Liquidate===');
      await usdc.connect(alice).approve(bank.address, ethers.constants.MaxUint256);
      await expect(bank.connect(alice).liquidate(positionId, USDC, ethers.constants.MaxUint256)).to.be.emit(
        bank,
        'Liquidate'
      );

      positionInfo = await bank.getPositionInfo(positionId);
      debtValue = await bank.callStatic.getDebtValue(positionId);
      positionValue = await bank.callStatic.getPositionValue(positionId);
      risk = await bank.callStatic.getPositionRisk(positionId);
      const collateralBalance = await colToken.balanceOf(alice.address, positionInfo.collId);
      console.log('Cur Pos:', positionInfo);
      console.log('Debt Value:', utils.formatUnits(debtValue));
      console.log('Position Value:', utils.formatUnits(positionValue));
      console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
      console.log('Position Size:', utils.formatUnits(positionInfo.collateralSize));
      console.log("Liquidator's Position Balance:", collateralBalance);
      console.log("Liquidator's Collateral Balance:", await uVToken.balanceOf(alice.address));

      const beforeIchiBalance = await ichi.balanceOf(alice.address);
      await wichi.connect(alice).burn(positionInfo.collId, ethers.constants.MaxUint256);
      const afterIchiBalance = await ichi.balanceOf(alice.address);
      console.log("Liquidator's ICHI Balance:", utils.formatUnits(afterIchiBalance.sub(beforeIchiBalance), 18));

      const lpBalance = await ichiVault.balanceOf(alice.address);
      await ichiVault.connect(alice).withdraw(lpBalance, alice.address);
    });
    it('should be able to maintain the position to get rid of liquidation', async () => {
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      let risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Position Risk:', risk);

      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(17).mul(6), // $0.6
        ]
      );
      risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Position Risk:', risk);
      const positionInfo = await bank.getPositionInfo(positionId);
      const bankInfo = await bank.getBankInfo(positionInfo.underlyingToken);
      console.log('Liquidity Threshold:', bankInfo.liqThreshold);
      expect(await bank.callStatic.isLiquidatable(positionId)).to.be.true;
      console.log('Is Liquidatable:', await bank.callStatic.isLiquidatable(positionId));

      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('increasePosition', [ICHI, depositAmount.div(2)])
      );

      risk = await bank.callStatic.getPositionRisk(positionId);
      console.log('Position Risk:', risk);
      expect(await bank.callStatic.isLiquidatable(positionId)).to.be.false;
    });
    it('should revert execution when it is liquidateable after execution', async () => {
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(17).mul(1), // $0.1
        ]
      );
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('increasePosition', [ICHI, depositAmount.div(3)])
        )
      ).to.be.revertedWithCustomError(bank, 'INSUFFICIENT_COLLATERAL');
    });
  });

  describe('Misc', () => {
    describe('Owner', () => {
      it('should be able to whitelist spells', async () => {
        await expect(
          bank.connect(alice).whitelistSpells([admin.address, alice.address], [true, true])
        ).to.be.revertedWith('Ownable: caller is not the owner');
        await expect(bank.whitelistSpells([admin.address], [true, true])).to.be.revertedWithCustomError(
          bank,
          'INPUT_ARRAY_MISMATCH'
        );

        await expect(
          bank.whitelistSpells([admin.address, constants.AddressZero], [true, true])
        ).to.be.revertedWithCustomError(bank, 'ZERO_ADDRESS');

        expect(await bank.isSpellWhitelisted(admin.address)).to.be.false;
        await bank.whitelistSpells([admin.address], [true]);
        expect(await bank.isSpellWhitelisted(admin.address)).to.be.true;
        await bank.whitelistSpells([admin.address], [false]);
        expect(await bank.isSpellWhitelisted(admin.address)).to.be.false;
      });
      it('should be able to whitelist standard ERC20 tokens', async () => {
        await expect(bank.connect(alice).whitelistTokens([WETH], [true])).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );

        await expect(bank.whitelistTokens([WETH, ICHI], [true])).to.be.revertedWithCustomError(
          bank,
          'INPUT_ARRAY_MISMATCH'
        );

        await expect(bank.whitelistTokens([ADDRESS.CRV], [true]))
          .to.be.revertedWithCustomError(bank, 'ORACLE_NOT_SUPPORT')
          .withArgs(ADDRESS.CRV);

        await bank.whitelistTokens([WETH, ICHI], [true, true]);
        expect(await bank.isTokenWhitelisted(WETH)).to.be.true;
        expect(await bank.isTokenWhitelisted(ICHI)).to.be.true;

        await bank.whitelistTokens([WETH, ICHI], [false, false]);
        expect(await bank.isTokenWhitelisted(WETH)).to.be.false;
        expect(await bank.isTokenWhitelisted(ICHI)).to.be.false;

        await bank.whitelistTokens([WETH, ICHI], [true, true]);
        expect(await bank.isTokenWhitelisted(WETH)).to.be.true;
        expect(await bank.isTokenWhitelisted(ICHI)).to.be.true;
      });
      it('should be able to whitelist ERC1155 tokens', async () => {
        await expect(bank.connect(alice).whitelistERC1155([werc20.address], true)).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );

        await expect(bank.whitelistERC1155([ethers.constants.AddressZero], true)).to.be.revertedWithCustomError(
          bank,
          'ZERO_ADDRESS'
        );

        await bank.whitelistERC1155([werc20.address], true);
        expect(await bank.isWrappedTokenWhitelisted(werc20.address)).to.be.true;

        await bank.whitelistERC1155([werc20.address], false);
        expect(await bank.isWrappedTokenWhitelisted(werc20.address)).to.be.false;

        await bank.whitelistERC1155([werc20.address], true);
        expect(await bank.isWrappedTokenWhitelisted(werc20.address)).to.be.true;
      });
      it('should be able to add bank', async () => {
        await expect(
          bank.connect(alice).addBank(USDC, usdcSoftVault.address, hardVault.address, 9000)
        ).to.be.revertedWith('Ownable: caller is not the owner');

        await expect(bank.addBank(ethers.constants.AddressZero, usdcSoftVault.address, hardVault.address, 9000))
          .to.be.revertedWithCustomError(bank, 'TOKEN_NOT_WHITELISTED')
          .withArgs(ethers.constants.AddressZero);
        await expect(
          bank.addBank(USDC, ethers.constants.AddressZero, hardVault.address, 9000)
        ).to.be.revertedWithCustomError(bank, 'ZERO_ADDRESS');
        await expect(
          bank.addBank(USDC, usdcSoftVault.address, ethers.constants.AddressZero, 9000)
        ).to.be.revertedWithCustomError(bank, 'ZERO_ADDRESS');
        await expect(bank.addBank(USDC, usdcSoftVault.address, hardVault.address, 7000))
          .to.be.revertedWithCustomError(bank, 'LIQ_THRESHOLD_TOO_LOW')
          .withArgs(7000);
        await expect(bank.addBank(USDC, usdcSoftVault.address, hardVault.address, 12000))
          .to.be.revertedWithCustomError(bank, 'LIQ_THRESHOLD_TOO_HIGH')
          .withArgs(12000);

        await expect(bank.addBank(USDC, usdcSoftVault.address, hardVault.address, 9000)).to.be.revertedWithCustomError(
          bank,
          'BTOKEN_ALREADY_ADDED'
        );

        const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
        const crvSoftVault = <SoftVault>await upgrades.deployProxy(
          SoftVault,
          [config.address, bCRV.address, 'Interest Bearing CRV', 'ibCRV', admin.address],
          {
            unsafeAllow: ['delegatecall'],
          }
        );
        await crvSoftVault.deployed();

        await expect(bank.addBank(USDC, crvSoftVault.address, hardVault.address, 9000)).to.be.revertedWithCustomError(
          bank,
          'BANK_ALREADY_LISTED'
        );
      });
      it('should be able to modify bank', async () => {
        await expect(
          bank.connect(alice).modifyBank(0, USDC, usdcSoftVault.address, hardVault.address, 9000)
        ).to.be.revertedWith('Ownable: caller is not the owner');
        await expect(bank.modifyBank(0, ethers.constants.AddressZero, usdcSoftVault.address, hardVault.address, 9000))
          .to.be.revertedWithCustomError(bank, 'TOKEN_NOT_WHITELISTED')
          .withArgs(ethers.constants.AddressZero);
        await expect(
          bank.modifyBank(0, USDC, ethers.constants.AddressZero, hardVault.address, 9000)
        ).to.be.revertedWithCustomError(bank, 'ZERO_ADDRESS');
        await expect(
          bank.modifyBank(0, USDC, usdcSoftVault.address, ethers.constants.AddressZero, 9000)
        ).to.be.revertedWithCustomError(bank, 'ZERO_ADDRESS');
        await expect(
          bank.modifyBank(0, USDC, usdcSoftVault.address, hardVault.address, 7000)
        ).to.be.revertedWithCustomError(bank, 'LIQ_THRESHOLD_TOO_LOW');
        await expect(
          bank.modifyBank(0, USDC, usdcSoftVault.address, hardVault.address, 12000)
        ).to.be.revertedWithCustomError(bank, 'LIQ_THRESHOLD_TOO_HIGH');
        await expect(
          bank.modifyBank(4, USDC, wethSoftVault.address, hardVault.address, 9000)
        ).to.be.revertedWithCustomError(bank, 'BANK_NOT_EXIST');
      });
      it('should be able to set bank status', async () => {
        await mockOracle.setPrice([ICHI], [BigNumber.from(10).pow(18).mul(5)]);
        await expect(bank.connect(alice).setBankStatus(0)).to.be.revertedWith('Ownable: caller is not the owner');

        await bank.setBankStatus(0);
        expect(await bank.isBorrowAllowed()).to.be.false;
        expect(await bank.isRepayAllowed()).to.be.false;
        expect(await bank.isLendAllowed()).to.be.false;

        const iface = new ethers.utils.Interface(SpellABI);
        const depositAmount = utils.parseUnits('100', 18);
        const borrowAmount = utils.parseUnits('300', 6);
        await ichi.approve(bank.address, ethers.constants.MaxUint256);

        await expect(
          bank.execute(
            0,
            spell.address,
            iface.encodeFunctionData('openPosition', [
              {
                strategyId: 0,
                collToken: ICHI,
                borrowToken: USDC,
                collAmount: depositAmount,
                borrowAmount: borrowAmount,
                farmingPoolId: 0,
              },
            ])
          )
        ).to.be.revertedWithCustomError(bank, 'LEND_NOT_ALLOWED');

        await bank.setBankStatus(4);
        expect(await bank.isBorrowAllowed()).to.be.false;
        expect(await bank.isRepayAllowed()).to.be.false;
        expect(await bank.isLendAllowed()).to.be.true;

        await expect(
          bank.execute(
            0,
            spell.address,
            iface.encodeFunctionData('openPosition', [
              {
                strategyId: 0,
                collToken: ICHI,
                borrowToken: USDC,
                collAmount: depositAmount,
                borrowAmount: borrowAmount,
                farmingPoolId: 0,
              },
            ])
          )
        ).to.be.revertedWithCustomError(bank, 'BORROW_NOT_ALLOWED');

        await bank.setBankStatus(7);
        await bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPosition', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: 0,
            },
          ])
        );
        const positionId = (await bank.getNextPositionId()).sub(1);
        const tick = await ichiVault.currentTick();
        TickMath.getSqrtRatioAtTick(tick);
        await ichi.approve(bank.address, ethers.constants.MaxUint256);

        await mockOracle.setPrice(
          [ICHI],
          [
            BigNumber.from(10).pow(16).mul(326), // $3.26
          ]
        );
        await expect(
          bank.execute(
            positionId,
            spell.address,
            iface.encodeFunctionData('closePosition', [
              {
                strategyId: 0,
                collToken: ICHI,
                borrowToken: USDC,
                amountRepay: ethers.constants.MaxUint256,
                amountPosRemove: ethers.constants.MaxUint256,
                amountShareWithdraw: ethers.constants.MaxUint256,
                amountOutMin: 1,
                amountToSwap: 0,
                swapData: '0x',
              },
            ])
          )
        ).to.be.revertedWithCustomError(bank, 'WITHDRAW_LEND_NOT_ALLOWED');

        await bank.setBankStatus(13);
        await expect(
          bank.execute(
            positionId,
            spell.address,
            iface.encodeFunctionData('closePosition', [
              {
                strategyId: 0,
                collToken: ICHI,
                borrowToken: USDC,
                amountRepay: ethers.constants.MaxUint256,
                amountPosRemove: ethers.constants.MaxUint256,
                amountShareWithdraw: ethers.constants.MaxUint256,
                amountOutMin: 1,
                amountToSwap: 0,
                swapData: '0x',
              },
            ])
          )
        ).to.be.revertedWithCustomError(bank, 'REPAY_NOT_ALLOWED');
      });
    });
    describe('Accrue', () => {
      it('anyone can call accrue functions by tokens', async () => {
        await expect(bank.accrue(ADDRESS.SUSHI))
          .to.be.revertedWithCustomError(bank, 'BANK_NOT_LISTED')
          .withArgs(ADDRESS.SUSHI);

        await bank.accrueAll([USDC, ICHI]);
      });
    });
    describe('View functions', async () => {
      it('should revert EXECUTOR call when the bank is not under execution', async () => {
        await expect(bank.EXECUTOR()).to.be.revertedWithCustomError(bank, 'NOT_UNDER_EXECUTION');
      });
      it('should be able to check if the oracle support the token', async () => {
        expect(await oracle.callStatic.isTokenSupported(ADDRESS.CRV)).to.be.false;
      });
      it('should revert getCurrentPositionInfo when not in exec', async () => {
        await expect(bank.getCurrentPositionInfo())
          .to.be.revertedWithCustomError(bank, 'BAD_POSITION')
          .withArgs(ethers.constants.MaxUint256);
      });
      it('should not reverted getPositionValue view function call when reward token oracle route is set wrongly', async () => {
        const depositAmount = utils.parseUnits('100', 18);
        const borrowAmount = utils.parseUnits('300', 6);
        const iface = new ethers.utils.Interface(SpellABI);

        await usdc.approve(bank.address, ethers.constants.MaxUint256);
        await ichi.approve(bank.address, ethers.constants.MaxUint256);
        await bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        );

        // set ICHI token oracle route wrongly
        oracle.setRoutes([ICHI], [ICHI]);

        const positionId = (await bank.getNextPositionId()).sub(1);
        const positionValue = await bank.callStatic.getPositionValue(positionId);
        expect(positionValue).to.be.gte(BigNumber.from(0));

        // set ICHI token oracle route correctly
        oracle.setRoutes([ICHI], [mockOracle.address]);
      });
    });
  });
});
