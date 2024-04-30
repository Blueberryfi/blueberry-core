import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BlueberryBank, MockOracle, WERC20, ERC20, ShortLongSpell, SoftVault } from '../../typechain-types';
import { ethers } from 'hardhat';
import { ADDRESS } from '../../constant';
import { ShortLongProtocol, evm_mine_blocks, fork, setupShortLongProtocol } from '../helpers';
import SpellABI from '../../abi/contracts/spell/ShortLongSpell.sol/ShortLongSpell.json';

import chai, { expect } from 'chai';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { BigNumber, utils } from 'ethers';
import { getParaswapCalldata } from '../helpers/paraswap';

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('ShortLong Spell mainnet fork', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let crv: ERC20;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: ShortLongSpell;
  let bank: BlueberryBank;
  let protocol: ShortLongProtocol;
  let daiSoftVault: SoftVault;

  before(async () => {
    await fork(1, 19272826);

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    crv = <ERC20>await ethers.getContractAt('ERC20', CRV);
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);

    protocol = await setupShortLongProtocol();
    bank = protocol.bank;
    spell = protocol.shortLongSpell;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;
    daiSoftVault = protocol.daiSoftVault;
  });

  const depositAmount = utils.parseUnits('120', 6); // 100 USDC
  const borrowAmount = utils.parseUnits('220', 18); // 200 Dollars
  const iface = new ethers.utils.Interface(SpellABI);

  before(async () => {
    await usdc.approve(bank.address, ethers.constants.MaxUint256);
    await crv.approve(bank.address, ethers.constants.MaxUint256);
  });

  it('should revert when opening position exceeds max LTV', async () => {
    const swapData = await getParaswapCalldata(CRV, DAI, borrowAmount.mul(4), spell.address, 100);

    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: USDC,
            borrowToken: CRV,
            collAmount: depositAmount,
            borrowAmount: borrowAmount.mul(22),
            farmingPoolId: 0,
          },
          swapData.data,
        ])
      )
    ).to.be.revertedWithCustomError(spell, 'EXCEED_MAX_LTV');
  });

  it('should revert when opening a position for non-existing strategy', async () => {
    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 5,
            collToken: USDC,
            borrowToken: CRV,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: 0,
          },
          '0x00',
        ])
      )
    )
      .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
      .withArgs(spell.address, 5);
  });

  it('should revert when opening a position for non-existing collateral', async () => {
    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: WETH,
            borrowToken: CRV,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: 0,
          },
          '0x00',
        ])
      )
    )
      .to.be.revertedWithCustomError(spell, 'COLLATERAL_NOT_EXIST')
      .withArgs(0, WETH);
  });

  it('should revert when opening a position for incorrect farming pool id', async () => {
    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: USDC,
            borrowToken: DAI,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: 0,
          },
          '0x00',
        ])
      )
    ).to.be.revertedWithCustomError(spell, 'INCORRECT_LP');
  });

  it('should be able to farm DAI', async () => {
    const positionId = await bank.getNextPositionId();
    console.log('Position ID:', positionId.toString());
    const beforeTreasuryBalance = await usdc.balanceOf(treasury.address);
    const swapData = await getParaswapCalldata(CRV, DAI, borrowAmount, spell.address, 100);

    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData('openPosition', [
        {
          strategyId: 0,
          collToken: USDC,
          borrowToken: CRV,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: 0,
        },
        swapData.data,
      ])
    );

    const bankInfo = await bank.getBankInfo(DAI);
    console.log('DAI Bank Info:', bankInfo);

    const pos = await bank.getPositionInfo(positionId);
    console.log('Position Info:', pos);
    console.log('Position Value:', await bank.callStatic.getPositionValue(1));
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(werc20.address);
    expect(pos.debtToken).to.be.equal(CRV);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
  });

  it('should be able to get position risk ratio', async () => {
    let risk = await bank.callStatic.getPositionRisk(1);
    let pv = await bank.callStatic.getPositionValue(1);
    let ov = await bank.callStatic.getDebtValue(1);
    let cv = await bank.callStatic.getIsolatedCollateralValue(1);
    console.log('PV:', utils.formatUnits(pv));
    console.log('OV:', utils.formatUnits(ov));
    console.log('CV:', utils.formatUnits(cv));
    console.log('Prev Position Risk', utils.formatUnits(risk, 2), '%');
    await mockOracle.setPrice(
      [DAI, USDC],
      [
        BigNumber.from(10).pow(17).mul(15), // $1.5
        BigNumber.from(10).pow(17).mul(5), // $0.5
      ]
    );
    risk = await bank.callStatic.getPositionRisk(1);
    pv = await bank.callStatic.getPositionValue(1);
    ov = await bank.callStatic.getDebtValue(1);
    cv = await bank.callStatic.getIsolatedCollateralValue(1);
    console.log('=======');
    console.log('PV:', utils.formatUnits(pv));
    console.log('OV:', utils.formatUnits(ov));
    console.log('CV:', utils.formatUnits(cv));
    console.log('Position Risk', utils.formatUnits(risk, 2), '%');
  });

  it('should revert when opening a position for non-existing strategy', async () => {
    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 5,
            collToken: USDC,
            borrowToken: CRV,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
          '0x00',
        ])
      )
    )
      .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
      .withArgs(spell.address, 5);
  });

  it('should revert when opening a position for non-existing collateral', async () => {
    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 0,
            collToken: WETH,
            borrowToken: CRV,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
          '0x00',
        ])
      )
    )
      .to.be.revertedWithCustomError(spell, 'COLLATERAL_NOT_EXIST')
      .withArgs(0, WETH);
  });

  it('should be able to close position partially', async () => {
    await evm_mine_blocks(10000);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);
    console.log('Position Info:', position);

    const debtAmount = await bank.callStatic.currentPositionDebt(positionId);
    console.log('Debt Amount:', utils.formatUnits(debtAmount));
    const swapAmount = (await daiSoftVault.callStatic.withdraw(position.collateralSize)).div(2);
    console.log('Swap Amount:', utils.formatUnits(swapAmount));
    // Manually transfer CRV rewards to spell
    await crv.transfer(spell.address, utils.parseUnits('3', 18));

    const beforeTreasuryBalance = await usdc.balanceOf(treasury.address);
    const beforeUSDCBalance = await usdc.balanceOf(admin.address);
    const beforeCrvBalance = await crv.balanceOf(admin.address);

    await mockOracle.setPrice(
      [DAI, USDC],
      [
        BigNumber.from(10).pow(18), // $1
        BigNumber.from(10).pow(18), // $1
      ]
    );

    const swapData = await getParaswapCalldata(DAI, CRV, swapAmount, spell.address, 100);
    console.log('Swap Data:', swapData.data);
    const iface = new ethers.utils.Interface(SpellABI);
    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData('closePosition', [
        {
          strategyId: 0,
          collToken: USDC,
          borrowToken: CRV,
          amountRepay: debtAmount.div(2),
          amountPosRemove: position.collateralSize.div(2),
          amountShareWithdraw: position.underlyingVaultShare.div(2),
          amountOutMin: 1,
          amountToSwap: 0,
          swapData: '0x',
        },
        swapData.data,
      ])
    );
    const afterUSDCBalance = await usdc.balanceOf(admin.address);
    const afterCrvBalance = await crv.balanceOf(admin.address);
    console.log('USDC Balance Change:', afterUSDCBalance.sub(beforeUSDCBalance));
    console.log('CRV Balance Change:', afterCrvBalance.sub(beforeCrvBalance));
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
    expect(afterCrvBalance.sub(beforeCrvBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

    const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.div(2));
  });

  it('should fail to close position', async () => {
    await evm_mine_blocks(10000);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);

    const swapAmount = (await daiSoftVault.callStatic.withdraw(position.collateralSize)).div(2);

    // Manually transfer CRV rewards to spell
    await crv.transfer(spell.address, utils.parseUnits('3', 18));

    await mockOracle.setPrice(
      [DAI, USDC],
      [
        BigNumber.from(10).pow(18), // $1
        BigNumber.from(10).pow(18), // $1
      ]
    );

    const swapData = await getParaswapCalldata(DAI, CRV, swapAmount, spell.address, 100);

    const iface = new ethers.utils.Interface(SpellABI);
    await expect(
      bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 0,
            collToken: USDC,
            borrowToken: CRV,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
          swapData.data,
        ])
      )
    )
      .to.be.revertedWithCustomError(spell, 'INCORRECT_LP')
      .withArgs(DAI);
  });

  it('should be able to close position', async () => {
    await evm_mine_blocks(10000);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);

    const swapAmount = await daiSoftVault.callStatic.withdraw(position.collateralSize);

    // Manually transfer CRV rewards to spell
    await crv.transfer(spell.address, utils.parseUnits('3', 18));

    const beforeTreasuryBalance = await usdc.balanceOf(treasury.address);
    const beforeUSDCBalance = await usdc.balanceOf(admin.address);
    const beforeCrvBalance = await crv.balanceOf(admin.address);

    await mockOracle.setPrice(
      [DAI, USDC],
      [
        BigNumber.from(10).pow(18), // $1
        BigNumber.from(10).pow(18), // $1
      ]
    );

    const swapData = await getParaswapCalldata(DAI, CRV, swapAmount, spell.address, 100);

    const iface = new ethers.utils.Interface(SpellABI);
    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData('closePosition', [
        {
          strategyId: 0,
          collToken: USDC,
          borrowToken: CRV,
          amountRepay: ethers.constants.MaxUint256,
          amountPosRemove: ethers.constants.MaxUint256,
          amountShareWithdraw: ethers.constants.MaxUint256,
          amountOutMin: 1,
          amountToSwap: 0,
          swapData: '0x',
        },
        swapData.data,
      ])
    );
    const afterUSDCBalance = await usdc.balanceOf(admin.address);
    const afterCrvBalance = await crv.balanceOf(admin.address);
    console.log('USDC Balance Change:', afterUSDCBalance.sub(beforeUSDCBalance));
    console.log('CRV Balance Change:', afterCrvBalance.sub(beforeCrvBalance));
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
    expect(afterCrvBalance.sub(beforeCrvBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

    const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.div(2));
  });
});
