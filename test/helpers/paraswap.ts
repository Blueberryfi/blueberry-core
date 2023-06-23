import axios from "axios";
import { constructSimpleSDK, SwapSide } from "@paraswap/sdk";
import { BigNumberish } from "ethers";

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
      maxImpact: maxImpact,
      otherExchangePrices: true,
    },
  });

  const calldata = await paraswapSdk.swap.buildTx(
    {
      srcToken: fromToken,
      destToken: toToken,
      srcAmount: amount.toString(),
      slippage: 3 * 0.01 * 10000, // 3% slippage
      priceRoute: priceRoute,
      userAddress: userAddr,
    },
    { ignoreChecks: true, ignoreGasEstimate: true }
  );

  return calldata;
};
