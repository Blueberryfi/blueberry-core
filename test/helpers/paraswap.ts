import axios from 'axios';
import { ethers } from 'hardhat';
import { OptimalRate, SwapSide, TransactionParams, constructSimpleSDK } from '@paraswap/sdk';
import { BigNumberish, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ERC20, IWETH } from '../../typechain-types';
import { setTokenBalance } from '.';

const paraswapSdk = constructSimpleSDK({
  chainId: 1,
  axios,
});

export const getParaswapCalldata = async (
  fromToken: string,
  toToken: string,
  amount: BigNumberish,
  userAddr: string,
  maxImpact?: number
) => {
  const priceRoute = await paraswapSdk.swap.getRate({
    srcToken: fromToken,
    destToken: toToken,
    amount: amount.toString(),
    options: {
      includeDEXS: ['SushiSwap', 'BalancerV1', 'BalancerV2', 'Curve', 'UniswapV3', 'CurveV2', 'CurveV3'],
      maxImpact: maxImpact,
      otherExchangePrices: false,
      excludeDEXS: ['UniswapV2'],
    },
  });

  const calldata = await paraswapSdk.swap.buildTx(
    {
      srcToken: fromToken,
      destToken: toToken,
      srcAmount: amount.toString(),
      slippage: 80 * 0.01 * 10000, // 30% slippage
      priceRoute: priceRoute,
      userAddress: userAddr,
    },
    { ignoreChecks: true, ignoreGasEstimate: true }
  );

  return calldata;
};

export const faucetToken = async (
  toToken: string,
  amount: BigNumberish,
  signer: SignerWithAddress,
  maxImpact?: number
): Promise<BigNumberish> => {
  if (toToken === ADDRESS.ETH) {
    return amount;
  }
  if (toToken === ADDRESS.WETH) {
    const weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, ADDRESS.WETH);

    await weth.connect(signer).deposit({ value: amount });
    return amount;
  }

  const token = <ERC20>await ethers.getContractAt('ERC20', toToken);
  try {
    await setTokenBalance(token, signer, utils.parseEther('100000'));
    return utils.parseEther('100000');
  } catch (e) {
    console.log(e);
  }

  const priceRoute = await paraswapSdk.swap.getRate({
    srcToken: ADDRESS.ETH,
    destToken: toToken,
    srcDecimals: 18,
    destDecimals: await token.decimals(),
    amount: amount.toString(),
    options: {
      includeDEXS: ['SushiSwap', 'BalancerV1', 'BalancerV2', 'Curve', 'UniswapV3', 'CurveV2', 'CurveV3'],
      maxImpact: maxImpact,
      otherExchangePrices: false,
      excludeDEXS: ['UniswapV2'],
    },
  });

  const preBalance = await token.balanceOf(signer.address);

  let txStatus = false;
  let retryCount = 1;
  while (txStatus === false) {
    try {
      const slippage = 10 * (0.01 + 0.001 * retryCount) * 10000;
      console.log(slippage);
      const calldata = await buildTxCalldata(toToken, amount, priceRoute, signer, slippage);

      await signer.sendTransaction({
        data: calldata.data,
        value: calldata.value,
        from: signer.address,
        to: ADDRESS.AUGUSTUS_SWAPPER,
      });
      txStatus = true;
    } catch (e) {
      retryCount++;

      if (retryCount > 10) {
        return 0;
      }
    }
  }
  return (await token.balanceOf(signer.address)).sub(preBalance);
};

export const getParaswapCalldataToBuy = async (
  fromToken: string,
  toToken: string,
  toAmount: BigNumberish,
  userAddr: string,
  maxImpact?: number
) => {
  const priceRoute = await paraswapSdk.swap.getRate({
    srcToken: fromToken,
    destToken: toToken,
    amount: toAmount.toString(),
    side: SwapSide.BUY,
    options: {
      includeDEXS: ['SushiSwap', 'BalancerV1', 'BalancerV2', 'Curve', 'UniswapV3', 'CurveV2', 'CurveV3'],
      maxImpact: maxImpact,
      otherExchangePrices: false,
      excludeDEXS: ['UniswapV2'],
    },
  });

  const calldata = await paraswapSdk.swap.buildTx(
    {
      srcToken: fromToken,
      destToken: toToken,
      destAmount: toAmount.toString(),
      slippage: 10 * 0.01 * 10000, // 10% slippage
      priceRoute: priceRoute,
      userAddress: userAddr,
    },
    { ignoreChecks: true, ignoreGasEstimate: true }
  );

  return {
    srcAmount: (priceRoute as any).srcAmount,
    calldata,
  };
};

async function buildTxCalldata(
  toToken: string,
  amount: BigNumberish,
  priceRoute: OptimalRate,
  signer: SignerWithAddress,
  slippage: number
): Promise<TransactionParams> {
  return await paraswapSdk.swap.buildTx(
    {
      srcToken: ADDRESS.ETH,
      destToken: toToken,
      srcAmount: amount.toString(),
      slippage: slippage,
      priceRoute: priceRoute,
      userAddress: signer.address,
    },
    { ignoreChecks: true, ignoreGasEstimate: true }
  );
}
