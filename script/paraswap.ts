import axios from 'axios';
import { constructSimpleSDK } from '@paraswap/sdk';
import { BigNumberish } from 'ethers';

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

const [fromToken, toToken, amount, userAddr, maxImpact] = process.argv.slice(2);

getParaswapCalldata(fromToken, toToken, amount, userAddr, Number(maxImpact)).then((res) => console.log(res.data));
