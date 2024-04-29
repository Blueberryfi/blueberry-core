import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, utils, Contract } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
  BlueberryBank,
  IchiSpell,
  MockOracle,
  WERC20,
  WIchiFarm,
  MockIchiVault,
  MockIchiFarm,
  ERC20,
  MockIchiV2,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import SpellABI from '../../abi/contracts/spell/IchiSpell.sol/IchiSpell.json';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { evm_mine_blocks, fork } from '../helpers';
import { Protocol, setupIchiProtocol } from '../helpers/setup-ichi-protocol';
import { TickMath } from '@uniswap/v3-sdk';

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const USDT = ADDRESS.USDT;
const ICHI = ADDRESS.ICHI;
const DAI = ADDRESS.DAI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const UNI_V3_ROUTER = ADDRESS.UNI_V3_ROUTER;

const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId

describe('ICHI Angel Vaults Spell', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let ichi: MockIchiV2;
  let ichiV1: ERC20;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: IchiSpell;
  let wichi: WIchiFarm;
  let bank: BlueberryBank;
  let ichiFarm: MockIchiFarm;
  let ichiVault: MockIchiVault;
  let daiVault: MockIchiVault;
  let protocol: Protocol;

  let bICHI: Contract;
  let bDAI: Contract;

  before(async () => {
    await fork(17089048);

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
    ichi = <MockIchiV2>await ethers.getContractAt('MockIchiV2', ICHI);
    ichiV1 = <ERC20>await ethers.getContractAt('ERC20', ICHIV1);

    protocol = await setupIchiProtocol();
    bank = protocol.bank;
    spell = protocol.ichiSpell;
    ichiFarm = protocol.ichiFarm;
    ichiVault = protocol.ichi_USDC_ICHI_Vault;
    daiVault = protocol.ichi_USDC_DAI_Vault;
    wichi = protocol.wichi;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;

    bICHI = protocol.bICHI;
    bDAI = protocol.bDAI;
  });

  beforeEach(async () => {});

  describe('Constructor', () => {
    it('should revert when zero address is provided in param', async () => {
      const IchiSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiSpell);
      await expect(
        upgrades.deployProxy(
          IchiSpell,
          [
            ethers.constants.AddressZero,
            werc20.address,
            WETH,
            wichi.address,
            UNI_V3_ROUTER,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(IchiSpell, 'ZERO_ADDRESS');
      await expect(
        upgrades.deployProxy(
          IchiSpell,
          [
            bank.address,
            ethers.constants.AddressZero,
            WETH,
            wichi.address,
            UNI_V3_ROUTER,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(IchiSpell, 'ZERO_ADDRESS');
      await expect(
        upgrades.deployProxy(
          IchiSpell,
          [
            bank.address,
            werc20.address,
            ethers.constants.AddressZero,
            wichi.address,
            UNI_V3_ROUTER,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(IchiSpell, 'ZERO_ADDRESS');
      await expect(
        upgrades.deployProxy(
          IchiSpell,
          [
            bank.address,
            werc20.address,
            WETH,
            ethers.constants.AddressZero,
            UNI_V3_ROUTER,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(IchiSpell, 'ZERO_ADDRESS');
    });
    it('should revert initializing twice', async () => {
      await expect(
        spell.initialize(
          bank.address,
          werc20.address,
          WETH,
          ethers.constants.AddressZero,
          UNI_V3_ROUTER,
          ADDRESS.AUGUSTUS_SWAPPER,
          ADDRESS.TOKEN_TRANSFER_PROXY,
          admin.address
        )
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });
  });

  describe('ICHI Vault Position', () => {
    const depositAmount = utils.parseUnits('10', 18); // worth of $400
    const borrowAmount = utils.parseUnits('30', 6);
    const iface = new ethers.utils.Interface(SpellABI);

    it('should revert when exceeds max LTV', async () => {
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
              borrowAmount: borrowAmount.mul(5),
              farmingPoolId: 0,
            },
          ])
        )
      ).to.be.revertedWithCustomError(spell, 'EXCEED_MAX_LTV');
    });
    it('should revert when below min isolated collateral size', async () => {
      // Min isolated collateral size is set to 10 USD
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
              collAmount: depositAmount.div(10),
              borrowAmount: utils.parseUnits('0.1', 6),
              farmingPoolId: 0,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'BELOW_MIN_ISOLATED_COLLATERAL')
        .withArgs(0);
    });
    it('should revert when exceeds max pos size', async () => {
      // Max position is set as 2,000
      await ichi.approve(bank.address, ethers.constants.MaxUint256);

      // Call openPosition with 1,500 is succeeded at the first time
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount.mul(40),
            borrowAmount: borrowAmount.mul(20), // 30 * 20 = 600 USDC
            farmingPoolId: 0,
          },
        ])
      );

      // Call openPosition with 1,500 is succeeded at the second time because position size is exceeded max position size
      const positionId = (await bank.getNextPositionId()).sub(1);
      await expect(
        bank.execute(
          positionId.toNumber(),
          spell.address,
          iface.encodeFunctionData('openPosition', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount.mul(40),
              borrowAmount: borrowAmount.mul(50), // 30 * 50 = 1,500 USDC
              farmingPoolId: 0,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'EXCEED_MAX_POS_SIZE')
        .withArgs(0);
    });
    it('should revert when opening a position with zero isolated collateral', async () => {
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
              collAmount: 0,
              borrowAmount: borrowAmount,
              farmingPoolId: 0,
            },
          ])
        )
      ).to.be.revertedWith('bad cast call');
    });
    it('should revert when opening a position with no borrows', async () => {
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
              borrowAmount: 0,
              farmingPoolId: 0,
            },
          ])
        )
      ).to.be.revertedWith('IV.deposit: deposits must be > 0');
    });
    it('should revert when opening a position for non-existing strategy', async () => {
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPosition', [
            {
              strategyId: 5,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: 0,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
        .withArgs(spell.address, 5);
    });
    it('should revert when opening a position with unsupported debt token', async () => {
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPosition', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: ADDRESS.DAI,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: 0,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'INCORRECT_DEBT')
        .withArgs(ADDRESS.DAI);
    });
    it('should revert when opening a position for non-existing collateral', async () => {
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPosition', [
            {
              strategyId: 0,
              collToken: USDT,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: 0,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'COLLATERAL_NOT_EXIST')
        .withArgs(0, USDT);
    });
    it('should be able to open a position for ICHI angel vault', async () => {
      const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
      const beforeICHIBalance = await ichi.balanceOf(bICHI.address);
      const beforeWrappedTokenBalance = await werc20.balanceOfERC20(ichiVault.address, bank.address);
      // Isolated collateral: ICHI
      // Borrow: USDC
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

      const fee = depositAmount.mul(50).div(10000);
      const afterICHIBalance = await ichi.balanceOf(bICHI.address);
      expect(afterICHIBalance.sub(beforeICHIBalance)).to.be.near(depositAmount.sub(fee));

      const positionId = (await bank.getNextPositionId()).sub(1);
      const pos = await bank.getPositionInfo(positionId);
      const afterWrappedTokenBalance = await werc20.balanceOfERC20(ichiVault.address, bank.address);
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(werc20.address);
      expect(pos.collId).to.be.equal(BigNumber.from(ichiVault.address));
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
      expect(afterWrappedTokenBalance.sub(beforeWrappedTokenBalance)).to.be.equal(pos.collateralSize);
      const bankInfo = await bank.getBankInfo(USDC);
      console.log('Bank Info', bankInfo, await bank.getBankInfo(ICHI));
      console.log('Position Info', pos);

      const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
    });
    it('should be able to open a position for DAI angel vault', async () => {
      await dai.approve(bank.address, ethers.constants.MaxUint256);
      const depositAmount = utils.parseUnits('400', 18); // worth of $400
      const borrowAmount = utils.parseUnits('30', 6);
      const beforeTreasuryBalance = await dai.balanceOf(treasury.address);
      const beforeDAIBalance = await dai.balanceOf(bDAI.address);
      const beforeWrappedTokenBalance = await werc20.balanceOfERC20(daiVault.address, bank.address);
      // Isolated collateral: DAI
      // Borrow: USDC
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 1,
            collToken: DAI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: 0,
          },
        ])
      );

      const fee = depositAmount.mul(50).div(10000);
      const afterDAIBalance = await dai.balanceOf(bDAI.address);
      expect(afterDAIBalance.sub(beforeDAIBalance)).to.be.near(depositAmount.sub(fee));

      const positionId = (await bank.getNextPositionId()).sub(1);
      const pos = await bank.getPositionInfo(positionId);
      const afterWrappedTokenBalance = await werc20.balanceOfERC20(daiVault.address, bank.address);
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(werc20.address);
      expect(pos.collId).to.be.equal(BigNumber.from(daiVault.address));
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
      expect(afterWrappedTokenBalance.sub(beforeWrappedTokenBalance)).to.be.equal(pos.collateralSize);
      const bankInfo = await bank.getBankInfo(USDC);
      console.log('Bank Info', bankInfo, await bank.getBankInfo(DAI));
      console.log('Position Info', pos);

      const afterTreasuryBalance = await dai.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
    });
    it('should be able to return position risk ratio', async () => {
      let risk = await bank.callStatic.getPositionRisk(1);
      console.log('Prev Position Risk', utils.formatUnits(risk, 2), '%');
      await mockOracle.setPrice(
        [USDC, ICHI],
        [
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(18).mul(4), // $4
        ]
      );
      risk = await bank.callStatic.getPositionRisk(1);
      console.log('Position Risk', utils.formatUnits(risk, 2), '%');
    });
    it('should revert when closing a position for non-existing strategy', async () => {
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          1,
          spell.address,
          iface.encodeFunctionData('closePosition', [
            {
              strategyId: 5,
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
        .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
        .withArgs(spell.address, 5);
    });
    it('should revert when closing a position for non-existing collateral', async () => {
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          1,
          spell.address,
          iface.encodeFunctionData('closePosition', [
            {
              strategyId: 0,
              collToken: USDT,
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
        .to.be.revertedWithCustomError(spell, 'COLLATERAL_NOT_EXIST')
        .withArgs(0, USDT);
    });
    it('should revert when closing a position which repays nothing', async () => {
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          1,
          spell.address,
          iface.encodeFunctionData('closePosition', [
            {
              strategyId: 5,
              collToken: ICHI,
              borrowToken: USDC,
              amountRepay: 0,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: 1,
              amountToSwap: 0,
              swapData: '0x',
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
        .withArgs(spell.address, 5);
    });

    it('should revert when token price is changed and outToken amount is out of slippage range', async () => {
      const positionId = (await bank.getNextPositionId()).sub(2);
      const positionInfo = await bank.getPositionInfo(positionId);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      await usdc.transfer(spell.address, utils.parseUnits('10', 6)); // manually set rewards

      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('closePosition', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              amountRepay: 0,
              amountPosRemove: positionInfo.collateralSize.div(3),
              amountShareWithdraw: 0,
              amountOutMin: utils.parseEther('10000'),
              amountToSwap: 0,
              swapData: '0x',
            },
          ])
        )
      ).to.be.revertedWith('Too little received');
    });
    it('should be able to close portion of position without withdrawing isolated collaterals', async () => {
      await mockOracle.setPrice(
        [USDC, ICHI],
        [
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(16).mul(326), // $3.26
        ]
      );
      const positionId = (await bank.getNextPositionId()).sub(2);
      const positionInfo = await bank.getPositionInfo(positionId);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      await usdc.transfer(spell.address, utils.parseUnits('10', 6)); // manually set rewards

      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);
      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            amountRepay: 0,
            amountPosRemove: positionInfo.collateralSize.div(3),
            amountShareWithdraw: 0,
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
        ])
      );
      const afterPositionInfo = await bank.getPositionInfo(positionId);
      expect(positionInfo.underlyingVaultShare).to.be.equal(afterPositionInfo.underlyingVaultShare);
    });
    it('should be able to close portion of position', async () => {
      const positionId = (await bank.getNextPositionId()).sub(2);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      await usdc.transfer(spell.address, utils.parseUnits('10', 6)); // manually set rewards

      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
      console.log('Treasury Balance:', beforeTreasuryBalance.toString());
      const beforeUSDCBalance = await usdc.balanceOf(admin.address);
      const beforeIchiBalance = await ichi.balanceOf(admin.address);
      const positionInfo = await bank.getPositionInfo(positionId);

      const iface = new ethers.utils.Interface(SpellABI);
      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            amountRepay: positionInfo.debtShare.div(3),
            amountPosRemove: positionInfo.collateralSize.div(3),
            amountShareWithdraw: positionInfo.underlyingVaultShare.div(3),
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
        ])
      );

      const afterUSDCBalance = await usdc.balanceOf(admin.address);
      const afterIchiBalance = await ichi.balanceOf(admin.address);
      console.log('USDC Balance Change:', afterUSDCBalance.sub(beforeUSDCBalance));
      console.log('ICHI Balance Change:', afterIchiBalance.sub(beforeIchiBalance));
      const depositFee = depositAmount.mul(50).div(10000);
      const withdrawFee = depositAmount.sub(depositFee).mul(50).div(30000);
      expect(afterIchiBalance.sub(beforeIchiBalance)).to.be.near(depositAmount.sub(depositFee).div(3).sub(withdrawFee));

      const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.near(withdrawFee);
    });
    it('should be able to withdraw USDC', async () => {
      const positionId = (await bank.getNextPositionId()).sub(2);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      await usdc.transfer(spell.address, utils.parseUnits('10', 6)); // manually set rewards

      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
      const beforeUSDCBalance = await usdc.balanceOf(admin.address);
      const beforeIchiBalance = await ichi.balanceOf(admin.address);

      const iface = new ethers.utils.Interface(SpellABI);
      await bank.execute(
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
      );

      const afterUSDCBalance = await usdc.balanceOf(admin.address);
      const afterIchiBalance = await ichi.balanceOf(admin.address);
      console.log('USDC Balance Change:', afterUSDCBalance.sub(beforeUSDCBalance));
      console.log('ICHI Balance Change:', afterIchiBalance.sub(beforeIchiBalance));
      const depositFee = depositAmount.mul(50).div(10000);
      const withdrawFee = depositAmount.sub(depositFee).mul(2).mul(50).div(30000);
      expect(afterIchiBalance.sub(beforeIchiBalance)).to.be.gte(
        depositAmount.sub(depositFee).mul(2).div(3).sub(withdrawFee)
      );

      const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.near(withdrawFee);
    });

    it('should be able to open a position for ICHI angel vault', async () => {
      const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
      const beforeICHIBalance = await ichi.balanceOf(bICHI.address);
      const beforeWrappedTokenBalance = await werc20.balanceOfERC20(ichiVault.address, bank.address);
      // Isolated collateral: ICHI
      // Borrow: ICHI
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: ICHI,
            collAmount: depositAmount,
            borrowAmount: utils.parseUnits('5', 18),
            farmingPoolId: 0,
          },
        ])
      );

      const fee = depositAmount.mul(50).div(10000);
      const afterICHIBalance = await ichi.balanceOf(bICHI.address);
      expect(afterICHIBalance.sub(beforeICHIBalance)).to.be.near(depositAmount.sub(fee).sub(utils.parseUnits('5', 18)));

      const positionId = (await bank.getNextPositionId()).sub(1);
      const pos = await bank.getPositionInfo(positionId);
      const afterWrappedTokenBalance = await werc20.balanceOfERC20(ichiVault.address, bank.address);
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(werc20.address);
      expect(pos.collId).to.be.equal(BigNumber.from(ichiVault.address));
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
      expect(afterWrappedTokenBalance.sub(beforeWrappedTokenBalance)).to.be.equal(pos.collateralSize);
      const bankInfo = await bank.getBankInfo(ICHI);
      console.log('Bank Info', bankInfo);
      console.log('Position Info', pos);

      const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
    });
    it('should be able to close portion of position', async () => {
      const positionId = (await bank.getNextPositionId()).sub(1);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);

      const positionInfo = await bank.getPositionInfo(positionId);

      const iface = new ethers.utils.Interface(SpellABI);
      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: ICHI,
            amountRepay: positionInfo.debtShare.div(3),
            amountPosRemove: 1,
            amountShareWithdraw: positionInfo.underlyingVaultShare.div(3),
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
        ])
      );
    });
    it('should be able to withdraw ICHI', async () => {
      const positionId = (await bank.getNextPositionId()).sub(1);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      await ichi.transfer(spell.address, utils.parseUnits('10', 18)); // manually set rewards

      const iface = new ethers.utils.Interface(SpellABI);
      await bank.execute(
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
      );
    });
  });

  describe('ICHI Vault Farming Position', () => {
    const depositAmount = utils.parseUnits('100', 18); // ICHI => $4.17 at current block
    const borrowAmount = utils.parseUnits('500', 6); // USDC
    const iface = new ethers.utils.Interface(SpellABI);

    beforeEach(async () => {
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
    });

    it('should revert when opening position exceeds max LTV', async () => {
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
              borrowAmount: borrowAmount.mul(3),
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      ).to.be.revertedWithCustomError(spell, 'EXCEED_MAX_LTV');
    });
    it('should revert when opening a position for non-existing strategy', async () => {
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 5,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
        .withArgs(spell.address, 5);
    });
    it('should revert when opening a position for non-existing collateral', async () => {
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: USDT,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'COLLATERAL_NOT_EXIST')
        .withArgs(0, USDT);
    });
    it('should revert when opening a position for incorrect farming pool id', async () => {
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
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
              farmingPoolId: ICHI_VAULT_PID + 1,
            },
          ])
        )
      ).to.be.revertedWithCustomError(spell, 'INCORRECT_LP');
    });
    it('should revert when closing a position for non-existing strategy', async () => {
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          1,
          spell.address,
          iface.encodeFunctionData('closePositionFarm', [
            {
              strategyId: 5,
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
        .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
        .withArgs(spell.address, 5);
    });
    it('should revert when closing a position for non-existing collateral', async () => {
      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          1,
          spell.address,
          iface.encodeFunctionData('closePositionFarm', [
            {
              strategyId: 0,
              collToken: USDT,
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
        .to.be.revertedWithCustomError(spell, 'COLLATERAL_NOT_EXIST')
        .withArgs(0, USDT);
    });
    it('should be able to farm USDC on ICHI angel vault', async () => {
      const positionId = await bank.getNextPositionId();
      const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);

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

      const bankInfo = await bank.getBankInfo(USDC);
      console.log(bankInfo);

      const pos = await bank.getPositionInfo(positionId);
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(wichi.address);
      expect(pos.debtToken).to.be.equal(USDC);
      const poolInfo = await ichiFarm.poolInfo(ICHI_VAULT_PID);
      const collId = await wichi.encodeId(ICHI_VAULT_PID, poolInfo.accIchiPerShare);
      expect(pos.collId).to.be.equal(collId);
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
      expect(await wichi.balanceOf(bank.address, collId)).to.be.equal(pos.collateralSize);

      const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
    });
    it('should be able to get position risk ratio', async () => {
      let risk = await bank.callStatic.getPositionRisk(2);
      console.log('Prev Position Risk', utils.formatUnits(risk, 2), '%');
      await mockOracle.setPrice(
        [USDC, ICHI],
        [
          BigNumber.from(10).pow(18), // $1
          BigNumber.from(10).pow(16).mul(326), // $3.26
        ]
      );
      risk = await bank.callStatic.getPositionRisk(2);
      console.log('Position Risk', utils.formatUnits(risk, 2), '%');
    });
    it('should revert increasing existing position when diff pos param given', async () => {
      const positionId = (await bank.getNextPositionId()).sub(1);
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 1,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: 1,
            },
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, 'INCORRECT_PID')
        .withArgs(1);
    });
    it('should be able to harvest on ICHI farming', async () => {
      evm_mine_blocks(1000);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      await usdc.transfer(spell.address, utils.parseUnits('10', 6)); // manually set rewards

      const tick = await ichiVault.currentTick();
      TickMath.getSqrtRatioAtTick(tick);

      const pendingIchi = await ichiFarm.pendingIchi(ICHI_VAULT_PID, wichi.address);
      console.log('Pending Rewards:', pendingIchi);
      await ichiV1.transfer(ichiFarm.address, pendingIchi.mul(100));

      const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
      const beforeUSDCBalance = await usdc.balanceOf(admin.address);
      const beforeIchiBalance = await ichi.balanceOf(admin.address);

      const positionId = (await bank.getNextPositionId()).sub(1);
      const iface = new ethers.utils.Interface(SpellABI);
      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('closePositionFarm', [
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
      );
      const afterUSDCBalance = await usdc.balanceOf(admin.address);
      const afterIchiBalance = await ichi.balanceOf(admin.address);
      console.log('USDC Balance Change:', afterUSDCBalance.sub(beforeUSDCBalance));
      console.log('ICHI Balance Change:', afterIchiBalance.sub(beforeIchiBalance));
      const depositFee = depositAmount.mul(50).div(10000);
      const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
      expect(afterIchiBalance.sub(beforeIchiBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

      const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
      // Plus rewards fee
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee);
    });
  });

  describe('Increase/decrease', () => {
    const depositAmount = utils.parseUnits('100', 18); // ICHI => $4.17 at current block
    const borrowAmount = utils.parseUnits('500', 6); // USDC
    const iface = new ethers.utils.Interface(SpellABI);

    beforeEach(async () => {
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
    });

    it('should revert when another strategyId provided', async () => {
      const nextPosId = await bank.getNextPositionId();
      await spell.addStrategy(alice.address, utils.parseUnits('50', 18), utils.parseUnits('2000', 18));
      await expect(
        bank.execute(
          nextPosId.sub(1),
          spell.address,
          iface.encodeFunctionData('reducePosition', [1, ICHI, depositAmount.div(2)])
        )
      )
        .to.be.revertedWithCustomError(spell, 'INCORRECT_STRATEGY_ID')
        .withArgs(1);
    });

    it('should revert when reducing position exceeds max LTV', async () => {
      const nextPosId = await bank.getNextPositionId();
      const positionId = nextPosId.sub(1);
      const positionInfo = await bank.getPositionInfo(positionId);
      const underlyingShareAmount = positionInfo.underlyingVaultShare;

      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData('reducePosition', [0, ICHI, underlyingShareAmount])
        )
      ).to.be.revertedWithCustomError(spell, 'EXCEED_MAX_LTV');
    });

    it('should be able to reduce position within maxLTV', async () => {
      const nextPosId = await bank.getNextPositionId();
      const positionId = nextPosId.sub(1);
      const positionInfo = await bank.getPositionInfo(positionId);
      const underlyingShareAmount = positionInfo.underlyingVaultShare;

      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('reducePosition', [0, ICHI, underlyingShareAmount.div(3)])
      );
    });

    it('should be able to increase position', async () => {
      const nextPosId = await bank.getNextPositionId();

      await bank.execute(
        nextPosId.sub(1),
        spell.address,
        iface.encodeFunctionData('increasePosition', [ICHI, depositAmount.div(3)])
      );
    });

    it('should be able to maintain the position with more deposits/borrows', async () => {
      const nextPosId = await bank.getNextPositionId();
      await bank.execute(
        nextPosId.sub(1),
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
    });

    it('should revert maintaining position when farming pool id does not match', async () => {
      const nextPosId = await bank.getNextPositionId();
      await expect(
        bank.execute(
          nextPosId.sub(1),
          spell.address,
          iface.encodeFunctionData('openPositionFarm', [
            {
              strategyId: 0,
              collToken: ICHI,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: ICHI_VAULT_PID + 1,
            },
          ])
        )
      ).to.be.revertedWithCustomError(spell, 'INCORRECT_LP');
    });
  });

  describe('Owner Functions', () => {
    let spell: IchiSpell;
    const minCollSize = utils.parseEther('100');
    const maxPosSize = utils.parseEther('200000');

    beforeEach(async () => {
      const IchiSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiSpell);
      spell = <IchiSpell>(
        await upgrades.deployProxy(
          IchiSpell,
          [
            bank.address,
            werc20.address,
            WETH,
            wichi.address,
            UNI_V3_ROUTER,
            ADDRESS.AUGUSTUS_SWAPPER,
            ADDRESS.TOKEN_TRANSFER_PROXY,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      );
      await spell.deployed();
    });

    describe('Add Strategy', () => {
      it('only owner should be able to add new strategies to the spell', async () => {
        await expect(spell.connect(alice).addStrategy(ichiVault.address, minCollSize, maxPosSize)).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );
      });
      it('should revert when vault address or maxPosSize is zero', async () => {
        await expect(
          spell.addStrategy(ethers.constants.AddressZero, minCollSize, maxPosSize)
        ).to.be.revertedWithCustomError(spell, 'ZERO_ADDRESS');
        await expect(spell.addStrategy(ichiVault.address, minCollSize, 0)).to.be.revertedWithCustomError(
          spell,
          'ZERO_AMOUNT'
        );
        await expect(spell.addStrategy(ichiVault.address, maxPosSize, maxPosSize)).to.be.revertedWithCustomError(
          spell,
          'INVALID_POS_SIZE'
        );
      });
      it('owner should be able to add strategy', async () => {
        await expect(spell.addStrategy(ichiVault.address, minCollSize, maxPosSize))
          .to.be.emit(spell, 'StrategyAdded')
          .withArgs(0, ichiVault.address, minCollSize, maxPosSize);
      });
      it('owner should be able to update max pos size', async () => {
        await spell.addStrategy(ichiVault.address, minCollSize, maxPosSize);
        await expect(spell.connect(alice).setPosSize(0, minCollSize, maxPosSize)).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );
        await expect(spell.setPosSize(10, minCollSize, maxPosSize))
          .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
          .withArgs(spell.address, 10);
        await expect(spell.setPosSize(0, minCollSize, 0)).to.be.revertedWithCustomError(spell, 'ZERO_AMOUNT');
        await expect(spell.setPosSize(0, maxPosSize, maxPosSize)).to.be.revertedWithCustomError(
          spell,
          'INVALID_POS_SIZE'
        );

        await expect(spell.setPosSize(0, minCollSize, maxPosSize)).to.be.emit(spell, 'StrategyPosSizeUpdated');
      });
    });

    describe('Add Collaterals', () => {
      beforeEach(async () => {
        await spell.addStrategy(ichiVault.address, minCollSize, maxPosSize);
      });
      it('only owner should be able to add collaterals', async () => {
        await expect(spell.connect(alice).setCollateralsMaxLTVs(0, [USDC, ICHI], [30000, 30000])).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );
      });
      it('should revert when adding collaterals for non-existing strategy', async () => {
        await expect(spell.setCollateralsMaxLTVs(1, [USDC, ICHI], [30000, 30000]))
          .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
          .withArgs(spell.address, 1);
      });
      it('should revert when collateral or maxLTV is zero', async () => {
        await expect(
          spell.setCollateralsMaxLTVs(0, [ethers.constants.AddressZero, ICHI], [30000, 30000])
        ).to.be.revertedWithCustomError(spell, 'ZERO_ADDRESS');
        await expect(spell.setCollateralsMaxLTVs(0, [USDC, ICHI], [0, 30000])).to.be.revertedWithCustomError(
          spell,
          'ZERO_AMOUNT'
        );
      });
      it('should revert when input array length does not match', async () => {
        await expect(spell.setCollateralsMaxLTVs(0, [USDC, ICHI, WETH], [30000, 30000])).to.be.revertedWithCustomError(
          spell,
          'INPUT_ARRAY_MISMATCH'
        );
        await expect(spell.setCollateralsMaxLTVs(0, [], [])).to.be.revertedWithCustomError(
          spell,
          'INPUT_ARRAY_MISMATCH'
        );
      });
      it('owner should be able to add collaterals', async () => {
        await expect(spell.setCollateralsMaxLTVs(0, [USDC, ICHI], [30000, 30000])).to.be.emit(
          spell,
          'CollateralsMaxLTVSet'
        );
      });
    });
  });
});
