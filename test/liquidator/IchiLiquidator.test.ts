import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { evm_increaseTime, evm_mine_blocks, fork, setupIchiProtocol } from '../helpers';
import {
  BlueberryBank,
  ERC20,
  IchiLiquidator,
  IchiSpell,
  MockIchiFarm,
  MockIchiV2,
  MockIchiVault,
  MockOracle,
  WIchiFarm,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import SpellABI from '../../abi/contracts/spell/IchiSpell.sol/IchiSpell.json';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';

const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const POOL_ADDRESSES_PROVIDER = ADDRESS.POOL_ADDRESSES_PROVIDER;
const UNISWAP_V3_ROUTER = ADDRESS.UNI_V3_ROUTER;
const WETH = ADDRESS.WETH;

describe('Ichi Liquidator', () => {
  const depositAmount = utils.parseUnits('100', 18); // worth of $400
  const borrowAmount = utils.parseUnits('300', 6);
  const iface = new ethers.utils.Interface(SpellABI);

  let positionId: BigNumber;
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;
  let emergengyFund: SignerWithAddress;

  let usdc: ERC20;
  let ichi: MockIchiV2;
  let ichiV1: ERC20;
  let mockOracle: MockOracle;
  let spell: IchiSpell;
  let wichi: WIchiFarm;
  let bank: BlueberryBank;
  let ichiFarm: MockIchiFarm;
  let ichiVault: MockIchiVault;
  let liquidator: IchiLiquidator;
  const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId

  before(async () => {
    await fork();

    [admin, alice, treasury, emergengyFund] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    ichi = <MockIchiV2>await ethers.getContractAt('MockIchiV2', ICHI);
    ichiV1 = <ERC20>await ethers.getContractAt('ERC20', ICHIV1);

    const protocol = await setupIchiProtocol();
    bank = protocol.bank;
    spell = protocol.ichiSpell;
    ichiFarm = protocol.ichiFarm;
    ichiVault = protocol.ichi_USDC_ICHI_Vault;
    wichi = protocol.wichi;
    mockOracle = protocol.mockOracle;
  });

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

    const LiquidatorFactory = await ethers.getContractFactory(CONTRACT_NAMES.IchiLiquidator);
    liquidator = <IchiLiquidator>await upgrades.deployProxy(
      LiquidatorFactory,
      [
        bank.address,
        treasury.address,
        emergengyFund.address,
        POOL_ADDRESSES_PROVIDER,
        spell.address,
        UNISWAP_V3_ROUTER,
        ichi.address,
        WETH,
        admin.address,
      ],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
  });
  it('should be able to liquidate the position => (OV - PV)/CV = LT', async () => {
    await evm_increaseTime(4 * 3600);
    await evm_mine_blocks(10);
    await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);

    const pendingIchi = await ichiFarm.pendingIchi(ICHI_VAULT_PID, wichi.address);

    await ichiV1.transfer(ichiFarm.address, pendingIchi.mul(100));
    await ichiFarm.updatePool(ICHI_VAULT_PID);

    console.log('===ICHI token dumped from $5 to $0.1===');
    await mockOracle.setPrice(
      [ICHI],
      [
        BigNumber.from(10).pow(17).mul(8), // $0.5
      ]
    );

    // Check if a position is liquidatable
    expect(await bank.isLiquidatable(positionId)).to.be.true;

    // Liquidate the position
    await liquidator.connect(admin).liquidate(positionId);

    // Expect the position to be fully closed
    expect((await bank.getPositionInfo(positionId)).at(4)).is.equal(0);
    expect((await bank.getPositionInfo(positionId)).at(6)).is.equal(0);
    expect((await bank.getPositionInfo(positionId)).at(7)).is.equal(0);

    // Expect the liquidator to have some CRV
    expect(await usdc.balanceOf(liquidator.address)).to.be.greaterThan(0);

    // Expect withdraws to revert if a non-admin tries to withdraw
    await expect(liquidator.connect(alice).withdraw([usdc.address])).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );

    // Withdraw the CRV to the treasury
    await liquidator.connect(admin).withdraw([usdc.address]);

    expect(await usdc.balanceOf(liquidator.address)).to.be.equal(0);
    expect(await usdc.balanceOf(treasury.address)).to.be.greaterThan(0);
  });
});
