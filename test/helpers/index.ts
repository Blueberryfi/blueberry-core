import { ethers, network } from "hardhat";
import dotenv from "dotenv";
import { BigNumber, Wallet } from "ethers";

dotenv.config();

export const latestBlockNumber = async () => {
  return await ethers.provider.getBlockNumber();
};

export const evm_increaseTime = async (seconds: number) => {
  await network.provider.send("evm_increaseTime", [seconds]);
  await network.provider.send("evm_mine", []);
};

export const evm_mine_blocks = async (n: number) => {
  await network.provider.send("evm_setAutomine", [false]);
  await network.provider.send("evm_setIntervalMining", [0]);

  for (let i = 0; i < n / 256; i++) {
    await network.provider.send("hardhat_mine", ["0x100"]);
  }

  let remaining = n - Math.floor(n / 256) * 256;
  if (remaining) {
    await network.provider.send("hardhat_mine", [
      BigNumber.from(remaining).toHexString(),
    ]);
  }

  await network.provider.send("evm_setAutomine", [true]);
};

export const currentTime = async () => {
  const blockNum = await latestBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  return block.timestamp;
};

export const fork = async (chainId: number = 1, blockNumber?: number) => {
  if (chainId === 1) {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://rpc.ankr.com/eth`,
            blockNumber,
          },
        },
      ],
    });
  } else if (chainId === 42161) {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://arb1.arbitrum.io/rpc`,
            blockNumber,
          },
        },
      ],
    });
  }
};

export const generateRandomAddress = () => {
  return Wallet.createRandom().address;
};

export * from "./setup-ichi-protocol";
export * from "./setup-curve-protocol";
export * from "./setup-convex-protocol";
export * from "./setup-aura-protocol";
export * from "./setup-short-long-protocol";
