import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  BlueberryBank,
  MockOracle,
  WERC20,
  ERC20,
  ShortLongSpell,
  SoftVault,
  WApxEth,
  IWERC4626,
  ShortLongSpell_ERC4626,
} from '../../typechain-types';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ShortLongERC4626Protocol, evm_mine_blocks, fork, setupShortLongERC4626Protocol } from '../helpers';
import SpellABI from '../../abi/ShortLongSpell.json';
import chai, { expect } from 'chai';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { BigNumber, Contract, utils } from 'ethers';
import { getParaswapCalldata } from '../helpers/paraswap';
import { wrapper } from '../../typechain-types/contracts';
// import { setupShortLongERC4626Protocol } from '../helpers/setup-short-long-erc-4626-protocol';

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const WBTC = ADDRESS.WBTC;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('ShortLongERC4626 Spell mainnet fork', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let crv: ERC20;
  let werc20: WERC20;
  let wApxEth: Contract;
  let mockOracle: MockOracle;
  let spell: ShortLongSpell_ERC4626;
  let bank: BlueberryBank;
  let protocol: ShortLongERC4626Protocol;
  let daiSoftVault: SoftVault;

  before(async () => {
    await fork(1, 19272826);

    [admin, alice, treasury] = await ethers.getSigners();
    crv = <ERC20>await ethers.getContractAt('ERC20', CRV);
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);

    protocol = await setupShortLongERC4626Protocol();
    bank = protocol.bank;
    spell = protocol.shortLongSpell as ShortLongSpell_ERC4626;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;
    daiSoftVault = protocol.daiSoftVault;
    wApxEth = protocol.wApxEth as WApxEth;
  });

  const depositAmount = utils.parseUnits('190', 6); // 100 USDC
  const borrowAmount = utils.parseUnits('220', 18); // 200 Dollars
  const iface = new ethers.utils.Interface(SpellABI);

  before(async () => {
    await usdc.approve(bank.address, ethers.constants.MaxUint256);
    await crv.approve(bank.address, ethers.constants.MaxUint256);
  });

  it('should revert when opening position exceeds max LTV', async () => {
    const swapData = await getParaswapCalldata(CRV, ADDRESS.pxETH, borrowAmount.mul(4), spell.address, 100);

    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: USDC,
            borrowToken: CRV,
            collAmount: 120,
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
            strategyId: 100,
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
      .withArgs(spell.address, 100);
  });

  it('should revert when opening a position for non-existing collateral', async () => {
    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: WBTC,
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
      .withArgs(0, WBTC);
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
            borrowToken: ADDRESS.pxETH,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: 0,
          },
          '0x00',
        ])
      )
    ).to.be.revertedWithCustomError(spell, 'INCORRECT_LP');
  });

  it('should be able to open a position', async () => {
    const positionId = await bank.getNextPositionId();
    const beforeTreasuryBalance = await usdc.balanceOf(treasury.address);
    const swapData = await getParaswapCalldata(CRV, ADDRESS.pxETH, borrowAmount, spell.address, 100);

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

    const pos = await bank.getPositionInfo(positionId);
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(wApxEth.address);
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
        1,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 0,
            collToken: ADDRESS.pxETH,
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
      .withArgs(0, ADDRESS.pxETH);
  });

  // it('should fail to close position', async () => {
  //   await evm_mine_blocks(10000);
  //   const positionId = (await bank.getNextPositionId()).sub(1);
  //   const position = await bank.getPositionInfo(positionId);
  //
  //   // const swapAmount = (await daiSoftVault.callStatic.withdraw(position.collateralSize)).div(2);
  //   const debtAmount = await bank.callStatic.currentPositionDebt(positionId);
  //   const pendingRewards = await wApxEth.callStatic.pendingRewards(position.collId, position.collateralSize.div(2));
  //   const amountPlusReward = position.collateralSize.div(2).add(pendingRewards.rewards[0]);
  //   const apxEth = await ethers.getContractAt('IERC4626', ADDRESS.apxETH);
  //   const shares = await apxEth.convertToShares(amountPlusReward);
  //   const redeemAmount = (await apxEth.previewRedeem(shares)).div(2);
  //
  //   console.log(redeemAmount);
  //
  //   const param = {
  //     strategyId: 0,
  //     collToken: USDC,
  //     borrowToken: CRV,
  //     amountRepay: ethers.constants.MaxUint256,
  //     amountPosRemove: ethers.constants.MaxUint256,
  //     amountShareWithdraw: ethers.constants.MaxUint256,
  //     amountOutMin: 1,
  //     amountToSwap: 0,
  //     swapData: '0x',
  //   };
  //   const burnAmount = param.amountPosRemove; //await bank.callStatic.takeCollateral(param.amountPosRemove);
  //   console.log('burn amount from test: ', burnAmount);
  //
  //   const swapAmount = await wApxEth
  //     .connect(bank.address)
  //     .callStatic.burn(position.collId, ethers.constants.MaxUint256);
  //   // console.log('swap amount from test: ', swapAmount, position.collId);
  //   //
  //   // swapAmount = param.amountPosRemove.div(2);
  //
  //   // Manually transfer CRV rewards to spell
  //   await crv.transfer(spell.address, utils.parseUnits('3', 18));
  //
  //   await mockOracle.setPrice(
  //     [DAI, USDC],
  //     [
  //       BigNumber.from(10).pow(18), // $1
  //       BigNumber.from(10).pow(18), // $1
  //     ]
  //   );
  //
  //   const swapData = await getParaswapCalldata(ADDRESS.pxETH, CRV, swapAmount, spell.address, 100);
  //
  //   const iface = new ethers.utils.Interface(SpellABI);
  //   await expect(
  //     bank.execute(
  //       positionId,
  //       spell.address,
  //       iface.encodeFunctionData('closePosition', [
  //         {
  //           strategyId: 0,
  //           collToken: USDC,
  //           borrowToken: CRV,
  //           amountRepay: ethers.constants.MaxUint256,
  //           amountPosRemove: ethers.constants.MaxUint256,
  //           amountShareWithdraw: ethers.constants.MaxUint256,
  //           amountOutMin: 1,
  //           amountToSwap: 0,
  //           swapData: '0x',
  //         },
  //         swapData.data,
  //       ])
  //     )
  //   )
  //     .to.be.revertedWithCustomError(spell, 'INCORRECT_LP')
  //     .withArgs(DAI);
  // });

  it('should be able to close position partially', async () => {
    await evm_mine_blocks(10000);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);
    const debtAmount = await bank.callStatic.currentPositionDebt(positionId);

    const burnAmount = position.collateralSize.div(2); //await bank.callStatic.takeCollateral(param.amountPosRemove);
    console.log('burn amount from test: ', burnAmount);

    const swapAmount = await wApxEth.connect(bank.address).callStatic.burn(position.collId, burnAmount);
    console.log('swap amount from test: ', swapAmount, position.collId);

    // Manually transfer CRV rewards to spell
    // await crv.transfer(spell.address, utils.parseUnits('3', 18));

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

    const borrowAmount = utils.parseUnits('159.38226058174149', 14); //utils.parseUnits('220', 18); // 200 Dollars 15939580629380846
    const swapData = await getParaswapCalldata(ADDRESS.pxETH, CRV, swapAmount, spell.address, 100);
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

    console.log('curv bal diff: ', afterCrvBalance.sub(beforeCrvBalance));

    // expect(afterCrvBalance.sub(beforeCrvBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

    const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
    // Plus rewards fee
    // expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.div(2));
  });

  it('should be able to close position', async () => {
    await evm_mine_blocks(10000);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);
    const debtAmount = await bank.callStatic.currentPositionDebt(positionId);

    const burnAmount = position.collateralSize.div(2); //await bank.callStatic.takeCollateral(param.amountPosRemove);
    console.log('burn amount from test: ', burnAmount);

    const swapAmount = await wApxEth.connect(bank.address).callStatic.burn(position.collId, burnAmount);
    console.log('swap amount from test: ', swapAmount, position.collId);

    // Manually transfer CRV rewards to spell
    // await crv.transfer(spell.address, utils.parseUnits('3', 18));

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

    const swapData = await getParaswapCalldata(ADDRESS.pxETH, CRV, swapAmount, spell.address, 100);
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

    console.log('curv bal diff: ', afterCrvBalance.sub(beforeCrvBalance));

    // expect(afterCrvBalance.sub(beforeCrvBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

    const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
    // Plus rewards fee
    // expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.div(2));
  });
});
