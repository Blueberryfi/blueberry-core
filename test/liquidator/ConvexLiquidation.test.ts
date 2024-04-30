import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BlueberryBank, MockOracle, ERC20, ConvexSpell, ConvexLiquidator } from '../../typechain-types';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { CvxProtocol, setupCvxProtocol, evm_mine_blocks, fork, evm_increaseTime } from '../helpers';
import SpellABI from '../../abi/contracts/spell/ConvexSpell.sol/ConvexSpell.json';

import chai, { expect } from 'chai';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { BigNumber, utils } from 'ethers';

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const BAL = ADDRESS.BAL;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const CVX = ADDRESS.CVX;
const POOL_ID_1 = ADDRESS.CVX_3Crv_Id;
const POOL_ADDRESSES_PROVIDER = ADDRESS.POOL_ADDRESSES_PROVIDER;
const UNISWAP_V3_ROUTER = ADDRESS.UNI_V3_ROUTER;
const BALANCER_VAULT = ADDRESS.BALANCER_VAULT;

describe('Convex Liquidator', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;
  let emergengyFund: SignerWithAddress;

  let usdc: ERC20;
  let mockOracle: MockOracle;
  let spell: ConvexSpell;
  let bank: BlueberryBank;
  let protocol: CvxProtocol;
  let liquidator: ConvexLiquidator;
  let positionId: BigNumber;
  let dai: ERC20;

  before(async () => {
    await fork(1);
    [admin, alice, treasury, emergengyFund] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);

    protocol = await setupCvxProtocol();

    bank = protocol.bank;
    spell = protocol.convexSpell;
    mockOracle = protocol.mockOracle;
    const iface = new ethers.utils.Interface(SpellABI);

    const depositAmount = utils.parseUnits('110', 18); // CRV => $100
    const borrowAmount = utils.parseUnits('250', 6); // USDC
    await usdc.approve(bank.address, ethers.constants.MaxUint256);
    await dai.approve(bank.address, ethers.constants.MaxUint256);

    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData('openPositionFarm', [
        {
          strategyId: 0,
          collToken: DAI,
          borrowToken: USDC,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: POOL_ID_1,
        },
        0,
      ])
    );
    positionId = (await bank.getNextPositionId()).sub(1);

    const LiquidatorFactory = await ethers.getContractFactory(CONTRACT_NAMES.ConvexLiquidator);
    liquidator = <ConvexLiquidator>await upgrades.deployProxy(
      LiquidatorFactory,
      [
        bank.address,
        treasury.address,
        emergengyFund.address,
        POOL_ADDRESSES_PROVIDER,
        spell.address,
        BALANCER_VAULT,
        UNISWAP_V3_ROUTER,
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

    console.log('===DAI token dumped from $5 to $0.008===');
    await mockOracle.setPrice(
      [DAI],
      [
        BigNumber.from(10).pow(15).mul(8), // $0.008
      ]
    );
    const crvPool = '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511';
    const cvxPool = '0xb576491f1e6e5e62f1d8f26062ee822b40b0e0d4';
    liquidator.connect(admin).setProtocolToken(CRV, true);
    liquidator.connect(admin).setProtocolToken(CVX, true);
    liquidator.connect(admin).setProtocolToken(BAL, true);

    liquidator.connect(admin).registerCurveRoute(CRV, WETH, crvPool);
    liquidator.connect(admin).registerBalancerRoute(CVX, WETH, cvxPool);
    liquidator.connect(admin).registerBalancerRoute(BAL, WETH, BALANCER_VAULT);

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
