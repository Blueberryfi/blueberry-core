import { ethers, network } from 'hardhat';
import dotenv from 'dotenv';
import { BigNumber, BigNumberish, Contract, Wallet, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

dotenv.config();

export const latestBlockNumber = async () => {
  return await ethers.provider.getBlockNumber();
};

export const evm_increaseTime = async (seconds: number) => {
  await ethers.provider.send('evm_increaseTime', [seconds]);
  await evm_mine_blocks(1);
};

export const evm_mine_blocks = async (n: number) => {
  for (let i = 0; i < n; i++) {
    await ethers.provider.send('evm_mine', []);
  }
};

export const currentTime = async () => {
  const blockNum = await latestBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  return block.timestamp;
};

export const fork = async (chainId: number = 1, blockNumber: number = 18695050) => {
  if (chainId === 1) {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
            blockNumber: blockNumber,
          },
        },
      ],
    });
  } else if (chainId === 42161) {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_ARB_API_KEY}`,
            blockNumber: blockNumber,
          },
        },
      ],
    });
  }
};

export const generateRandomAddress = () => {
  return Wallet.createRandom().address;
};

export async function setBalance(address: string, balance: BigNumber) {
  await network.provider.send('hardhat_setBalance', [address, dirtyFix(balance._hex)]);
}

export async function mintToken(
  token: Contract,
  account: SignerWithAddress | Contract | string,
  amount: BigNumber | number | string
) {
  const index = await bruteForceTokenBalanceSlotIndex(token.address);

  const slot = dirtyFix(
    utils.keccak256(encodeSlot(['address', 'uint'], [typeof account === 'string' ? account : account.address, index]))
  );

  const prevAmount = await network.provider.send('eth_getStorageAt', [token.address, slot, 'latest']);

  await network.provider.send('hardhat_setStorageAt', [
    token.address,
    slot,
    encodeSlot(['uint'], [dirtyFix(BigNumber.from(amount).add(prevAmount))]),
  ]);
}

export async function setTokenBalance(
  token: Contract,
  account: SignerWithAddress | Contract,
  newBalance: BigNumber | number | string
) {
  const index = await bruteForceTokenBalanceSlotIndex(token.address);

  const slot = dirtyFix(utils.keccak256(encodeSlot(['address', 'uint'], [account.address, index])));

  await network.provider.send('hardhat_setStorageAt', [
    token.address,
    slot,
    encodeSlot(['uint'], [dirtyFix(BigNumber.from(newBalance))]),
  ]);
}

function encodeSlot(types: string[], values: any[]) {
  return utils.defaultAbiCoder.encode(types, values);
}

// source:  https://blog.euler.finance/brute-force-storage-layout-discovery-in-erc20-contracts-with-hardhat-7ff9342143ed
async function bruteForceTokenBalanceSlotIndex(tokenAddress: string): Promise<number> {
  const account = ethers.constants.AddressZero;

  const probeA = encodeSlot(['uint'], [1]);
  const probeB = encodeSlot(['uint'], [2]);

  const token = await ethers.getContractAt('ERC20', tokenAddress);

  for (let i = 0; i < 100; i++) {
    let probedSlot = utils.keccak256(encodeSlot(['address', 'uint'], [account, i])); // remove padding for JSON RPC

    const prev = await network.provider.send('eth_getStorageAt', [tokenAddress, probedSlot, 'latest']);

    while (probedSlot.startsWith('0x0')) probedSlot = '0x' + probedSlot.slice(3);

    // make sure the probe will change the slot value
    const probe = prev === probeA ? probeB : probeA;

    await network.provider.send('hardhat_setStorageAt', [tokenAddress, probedSlot, probe]);

    const balance = await token.balanceOf(account); // reset to previous value
    await network.provider.send('hardhat_setStorageAt', [tokenAddress, probedSlot, prev]);

    if (balance.eq(ethers.BigNumber.from(probe))) return i;
  }
  throw 'Balances slot not found!';
}

// WTF
// https://github.com/nomiclabs/hardhat/issues/1585
const dirtyFix = (s: string | BigNumber): string => {
  return s.toString().replace(/0x0+/, '0x');
};

export const addEthToContract = async (signer: SignerWithAddress, amount: BigNumberish, to: string) => {
  const MockEthSender = await ethers.getContractFactory('MockEthSender');
  const ethSender = await MockEthSender.deploy();

  await signer.sendTransaction({
    from: signer.address,
    to: ethSender.address,
    value: amount,
  });

  await ethSender.destruct(to);
};

export const impersonateAccount = async (account: string) => {
  await network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [account],
  });
};

export const takeSnapshot = async (): Promise<number> => {
  const snapshotId = await ethers.provider.send('evm_snapshot', []);
  return snapshotId;
};

export const revertToSnapshot = async (snapshotId: number) => {
  await ethers.provider.send('evm_revert', [snapshotId]);
};

export * from './setup-ichi-protocol';
export * from './setup-convex-protocol';
export * from './setup-aura-protocol';
export * from './setup-short-long-protocol';
