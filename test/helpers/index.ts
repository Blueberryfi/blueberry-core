import { ethers, network } from "hardhat";
import dotenv from "dotenv";
import { Wallet } from "ethers";

dotenv.config();

export const latestBlockNumber = async () => {
  return await ethers.provider.getBlockNumber();
};

export const evm_increaseTime = async (seconds: number) => {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await evm_mine_blocks(1);
};

export const evm_mine_blocks = async (n: number) => {
  for (let i = 0; i < n; i++) {
    await ethers.provider.send("evm_mine", []);
  }
};

export const currentTime = async() => {
  const blockNum = await latestBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  return block.timestamp;
}

export const fork = async (chainId: number = 1, blockNumber?: number) => {
  if (chainId === 1) {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth.llamarpc.com/rpc/${process.env.LLAMA_API_KEY}`,
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
  return Wallet.createRandom().address
};

export * from "./setup-ichi-protocol";
export * from "./setup-curve-protocol";
export * from "./setup-convex-protocol";
export * from "./setup-aura-protocol";
export * from "./setup-short-long-protocol";
