import { ethers, network } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, constants, utils } from 'ethers';
import { BlueberryBank, ERC20, CoreOracle, WERC20, PendleSpell } from '../../../../typechain-types';
import { ADDRESS } from '../../../../constant';
import { setupStrategy, strategies } from './utils';
import { evm_mine_blocks, fork, setTokenBalance } from '../../../helpers';
import SpellABI from '../../../../abi/contracts/spell/PendleSpell.sol/PendleSpell.json';
import { Router, toAddress } from '@pendle/sdk-v2';
import PendleRouterABI from '../../../../abi/contracts/interfaces/pendle-v2/IPendleRouter.sol/IPendleRouter.json';

const WETH = ADDRESS.WETH;
/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Pendle Spell Strategy test', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let snapshotId: any;

  let bank: BlueberryBank;
  let oracle: CoreOracle;
  let spell: PendleSpell;
  let werc20: WERC20;

  let collateralToken: ERC20;
  let borrowToken: ERC20;
  let depositAmount: BigNumber;
  let borrowAmount: BigNumber;
  let startingBlock: number;

  before(async () => {
    startingBlock = 20185000;
    await fork(1, startingBlock);

    [admin, alice, bob] = await ethers.getSigners();

    const strat = await setupStrategy();
    bank = strat.protocol.bank;
    oracle = strat.protocol.oracle;
    spell = strat.pendleSpell;
    werc20 = strat.werc20;
  });

  const counter = 0;
  for (let i = 0; i < strategies.length; i += 1) {
    const strategyInfo = strategies[i];
    for (let j = 0; j < strategyInfo.collateralAssets.length; j += 1) {
      for (let l = 0; l < strategyInfo.borrowAssets.length; l += 1) {
        describe(`Pendle Spell Test(collateral: ${strategyInfo.collateralAssets[j]} borrow: ${strategyInfo.borrowAssets[l]})`, () => {
          before(async () => {
            collateralToken = await ethers.getContractAt('ERC20', strategyInfo.collateralAssets[j]);
            borrowToken = await ethers.getContractAt('ERC20', strategyInfo.borrowAssets[l]);

            if (borrowToken.address === WETH) {
              depositAmount = utils.parseUnits('1', await collateralToken.decimals());
              borrowAmount = utils.parseUnits('1.8', await borrowToken.decimals());
            } else {
              depositAmount = utils.parseUnits('1000', await collateralToken.decimals());
              borrowAmount = utils.parseUnits('1800', await borrowToken.decimals());
            }

            await setTokenBalance(collateralToken, alice, depositAmount);
            await setTokenBalance(borrowToken, alice, borrowAmount);
            snapshotId = await network.provider.send('evm_snapshot');
          });

          it('should be able to open a position', async () => {
            await collateralToken.connect(alice).approve(bank.address, depositAmount);
            await borrowToken.connect(alice).approve(ADDRESS.PENDLE_ROUTER, constants.MaxUint256);

            const iface = new ethers.utils.Interface(SpellABI);

            await bank.connect(alice).execute(
              0,
              spell.address,
              iface.encodeFunctionData('openPosition', [
                {
                  strategyId: i,
                  collToken: collateralToken.address,
                  collAmount: depositAmount,
                  borrowToken: borrowToken.address,
                  borrowAmount: borrowAmount,
                  farmingPoolId: 0,
                },
                await generateExactTokenForPtData(
                  {
                    chainId: 1,
                    receiverAddr: spell.address,
                    marketAddr: strategyInfo.market,
                    tokenInAddr: borrowToken.address,
                    syTokenInAddr: '',
                    amountTokenIn: borrowAmount,
                    slippage: 0.1,
                    excludedSources: [],
                  },
                  alice,
                  startingBlock
                ),
              ])
            );

            const position = await bank.getPositionInfo(1);

            expect(position.collToken).to.be.eq(werc20.address);
            expect(position.underlyingToken).to.be.eq(collateralToken.address);
            expect(position.debtToken).to.be.eq(borrowToken.address);
          });
          it('should be able to close a position', async () => {
            await evm_mine_blocks(1000);
            const blockNumber = await ethers.provider.getBlockNumber();
            const positionInfo = await bank.getPositionInfo(1);
            const iface = new ethers.utils.Interface(SpellABI);
            await bank.connect(alice).execute(
              1,
              spell.address,
              iface.encodeFunctionData('closePosition', [
                {
                  strategyId: i,
                  collToken: collateralToken.address,
                  borrowToken: borrowToken.address,
                  amountRepay: ethers.constants.MaxUint256,
                  amountPosRemove: ethers.constants.MaxUint256,
                  amountShareWithdraw: ethers.constants.MaxUint256,
                  amountOutMin: 1,
                  amountToSwap: 0,
                  swapData: '0x',
                },
                await generateCloseData(
                  {
                    chainId: 1,
                    receiverAddr: spell.address,
                    marketAddr: strategyInfo.market,
                    exactPtIn: positionInfo.collateralSize,
                    tokenOutAddr: positionInfo.debtToken,
                    slippage: '1',
                    excludedSources: [],
                  },
                  alice,
                  blockNumber
                ),
              ])
            );

            const position = await bank.getPositionInfo(1);
            expect(position.debtShare).to.be.eq(0);
            expect(position.collateralSize).to.be.eq(0);
            expect(position.underlyingVaultShare).to.be.eq(0);

            await network.provider.send('evm_revert', [snapshotId]);
          });
        });
      }
    }
  }
});

type SwapExactTokenForPtBody = {
  chainId: number;
  receiverAddr: string;
  marketAddr: string;
  tokenInAddr: string;
  syTokenInAddr: string;
  amountTokenIn: BigNumber;
  slippage: number;
  excludedSources: string[];
};

async function generateExactTokenForPtData(
  requestBody: SwapExactTokenForPtBody,
  signer: SignerWithAddress,
  blockNumber: number
) {
  const router = Router.getRouterWithKyberAggregator({
    chainId: 1,
    provider: signer.provider || ethers.getDefaultProvider(),
    signer: signer,
  });

  const contractCall = await router.swapExactTokenForPt(
    toAddress(requestBody.marketAddr),
    toAddress(requestBody.tokenInAddr),
    requestBody.amountTokenIn,
    requestBody.slippage,
    {
      receiver: toAddress(requestBody.receiverAddr),
      method: 'getContractCall',
    }
  );

  const iface = new ethers.utils.Interface(PendleRouterABI);

  const functionData = iface.encodeFunctionData('swapExactTokenForPt', contractCall.params);

  return '0x'.concat(functionData.slice(10));
}

type SwapExactPtForTokenBody = {
  chainId: number;
  receiverAddr: string;
  marketAddr: string;
  exactPtIn: BigNumber;
  tokenOutAddr: string;
  slippage: string;
  excludedSources: string[];
};

async function generateCloseData(requestBody: SwapExactPtForTokenBody, signer: SignerWithAddress, blockNumber: number) {
  const router = Router.getRouterWithKyberAggregator({
    chainId: 1,
    provider: signer.provider || ethers.getDefaultProvider(),
    signer: signer,
  });

  try {
    const contractCall = await router.swapExactPtForToken(
      toAddress(requestBody.marketAddr),
      requestBody.exactPtIn,
      toAddress(requestBody.tokenOutAddr),
      1,
      {
        receiver: toAddress(requestBody.receiverAddr),
        aggregatorRequiredSigner: false,
        method: 'getContractCall',
      }
    );

    const iface = new ethers.utils.Interface(PendleRouterABI);
    const functionData = iface.encodeFunctionData('swapExactPtForToken', contractCall.params);

    return '0x'.concat(functionData.slice(10));
  } catch {
    const market = await ethers.getContractAt('IPMarket', requestBody.marketAddr);
    const yt = (await market.readTokens())._YT;

    const contractCall = await router.redeemPyToToken(
      toAddress(yt),
      requestBody.exactPtIn,
      toAddress(requestBody.tokenOutAddr),
      1,
      {
        method: 'getContractCall',
        aggregatorRequiredSigner: false,
        overrides: {
          blockTag: blockNumber,
        },
      }
    );

    const iface = new ethers.utils.Interface(PendleRouterABI);

    const functionData = iface.encodeFunctionData('redeemPyToToken', contractCall.params);

    return '0x'.concat(functionData.slice(10));
  }
}
