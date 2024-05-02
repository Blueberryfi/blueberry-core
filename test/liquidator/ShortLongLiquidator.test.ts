import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { BlueberryBank, ERC20, MockOracle, ShortLongLiquidator, ShortLongSpell } from '../../typechain-types';
import { ethers, upgrades } from 'hardhat';
import { setupShortLongProtocol } from '../helpers/setup-short-long-protocol';
import { BigNumber, utils } from 'ethers';
import SpellABI from '../../abi/contracts/spell/ShortLongSpell.sol/ShortLongSpell.json';
import { getParaswapCalldata } from '../helpers/paraswap';
import { evm_increaseTime, evm_mine_blocks } from '../helpers';
import { expect } from 'chai';

const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const SWAP_ROUTER = ADDRESS.UNI_V3_ROUTER;
const POOL_ADDRESSES_PROVIDER = ADDRESS.POOL_ADDRESSES_PROVIDER;
const BALANCER_VAULT = ADDRESS.BALANCER_VAULT;

describe('ShortLong Liquidator', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;
  let emergengyFund: SignerWithAddress;

  let usdc: ERC20;
  let crv: ERC20;
  let mockOracle: MockOracle;
  let spell: ShortLongSpell;
  let bank: BlueberryBank;
  let liquidator: ShortLongLiquidator;
  let positionId: BigNumber;

  before(async () => {
    [admin, alice, treasury, emergengyFund] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    crv = <ERC20>await ethers.getContractAt('ERC20', CRV);
    const protocol = await setupShortLongProtocol();

    bank = protocol.bank;
    spell = protocol.shortLongSpell;
    mockOracle = protocol.mockOracle;

    const LiquidatorFactory = await ethers.getContractFactory(CONTRACT_NAMES.ShortLongLiquidator);
    liquidator = <ShortLongLiquidator>await upgrades.deployProxy(
      LiquidatorFactory,
      [
        bank.address,
        treasury.address,
        emergengyFund.address,
        POOL_ADDRESSES_PROVIDER,
        spell.address,
        BALANCER_VAULT,
        SWAP_ROUTER,
        WETH,
        admin.address,
      ],
      {
        unsafeAllow: ['delegatecall'],
      }
    );

    const depositAmount = utils.parseUnits('100', 6); // 100 USDC
    const borrowAmount = utils.parseUnits('100', 18); // 100 CRV
    const iface = new ethers.utils.Interface(SpellABI);

    await mockOracle.setPrice(
      [CRV],
      [
        BigNumber.from(10).pow(17).mul(4), // $0.4
      ]
    );

    await usdc.approve(bank.address, ethers.constants.MaxUint256);
    await crv.approve(bank.address, ethers.constants.MaxUint256);
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

    positionId = (await bank.getNextPositionId()).sub(1);
  });

  it('should be able to liquidate the position => (OV - PV)/CV = LT', async () => {
    console.log('===CRV token jumps to $63===');
    await mockOracle.setPrice(
      [CRV],
      [
        BigNumber.from(10).pow(18).mul(63), // $63
      ]
    );

    await evm_increaseTime(4 * 3600);
    await evm_mine_blocks(10);

    // Check if a position is liquidatable
    expect(await bank.isLiquidatable(positionId)).to.be.true;

    // Liquidate the position
    await liquidator.connect(admin).liquidate(positionId);

    // Expect the position to be fully closed
    expect((await bank.getPositionInfo(positionId)).at(4)).is.equal(0);
    expect((await bank.getPositionInfo(positionId)).at(6)).is.equal(0);
    expect((await bank.getPositionInfo(positionId)).at(7)).is.equal(0);

    // Expect the liquidator to have some CRV
    expect(await crv.balanceOf(liquidator.address)).to.be.greaterThan(0);

    // Expect withdraws to revert if a non-admin tries to withdraw
    await expect(liquidator.connect(alice).withdraw([crv.address])).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );

    // Withdraw the CRV to the treasury
    await liquidator.connect(admin).withdraw([crv.address]);

    expect(await crv.balanceOf(liquidator.address)).to.be.equal(0);
    expect(await crv.balanceOf(treasury.address)).to.be.greaterThan(0);
  });
});
