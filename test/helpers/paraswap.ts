import axios from "axios";
import { ethers } from "hardhat";
import { constructSimpleSDK } from "@paraswap/sdk";
import { BigNumber, BigNumberish } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import { IWETH } from "../../typechain-types";

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
      includeDEXS: ["UniswapV2", "SushiSwap", "BalancerV1"],
      maxImpact: maxImpact,
      otherExchangePrices: true,
    },
  });

  const calldata = await paraswapSdk.swap.buildTx(
    {
      srcToken: fromToken,
      destToken: toToken,
      srcAmount: amount.toString(),
      slippage: 10 * 0.01 * 10000, // 10% slippage
      priceRoute: priceRoute,
      userAddress: userAddr,
    },
    { ignoreChecks: true, ignoreGasEstimate: true }
  );

  return calldata;
};

export const swapEth = async (
  toToken: string,
  amount: BigNumberish,
  signer: SignerWithAddress,
  maxImpact?: number
): Promise<BigNumberish> => {
  if (toToken === ADDRESS.ETH) {
    return amount;
  }
  if (toToken === ADDRESS.WETH) {
    const weth = <IWETH>(
      await ethers.getContractAt(CONTRACT_NAMES.IWETH, ADDRESS.WETH)
    );

    await weth.connect(signer).deposit({ value: amount });
    return amount;
  }
  const priceRoute = await paraswapSdk.swap.getRate({
    srcToken: ADDRESS.ETH,
    destToken: toToken,
    amount: amount.toString(),
    options: {
      includeDEXS: ["UniswapV2", "SushiSwap", "BalancerV1"],
      maxImpact: maxImpact,
      otherExchangePrices: true,
    },
  });

  const calldata = await paraswapSdk.swap.buildTx(
    {
      srcToken: ADDRESS.ETH,
      destToken: toToken,
      srcAmount: amount.toString(),
      slippage: 10 * 0.01 * 10000, // 10% slippage
      priceRoute: priceRoute,
      userAddress: signer.address,
    },
    { ignoreChecks: true, ignoreGasEstimate: true }
  );

  await signer.sendTransaction({
    data: calldata.data,
    value: calldata.value,
    from: signer.address,
    to: ADDRESS.AUGUSTUS_SWAPPER,
  });

  return BigNumber.from(priceRoute.destAmount).mul(90).div(100);
};
