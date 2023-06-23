import axios from "axios";
import { constructSimpleSDK, SwapSide } from "@paraswap/sdk";
import { BigNumberish } from "ethers";

const paraswapSdk = constructSimpleSDK({
  chainId: 1,
  axios,
});

export const getParaswaCalldata = async (
  fromToken: string,
  toToken: string,
  amount: BigNumberish,
  userAddr: string
) => {
  const priceRoute = await paraswapSdk.swap.getRate({
    srcToken: fromToken,
    destToken: toToken,
    amount: amount.toString(),
    options: {
      otherExchangePrices: true,
    },
  });

  const calldata = await paraswapSdk.swap.buildTx(
    {
      srcToken: fromToken,
      destToken: toToken,
      srcAmount: amount.toString(),
      slippage: 300,
      priceRoute,
      userAddress: userAddr,
    },
    { ignoreChecks: true }
  );

  return calldata;
};
