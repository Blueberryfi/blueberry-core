import { BigNumber, utils } from 'ethers';

export type HardVaultDeployment = {
  baseRate: number;
  multiplier: number;
  jumpMultiplier: number;
  kink1: number;
  roof: number;
};

const baseRate = '0';
const multiplier = utils.parseEther('0.4');
const jumpMultiplier = utils.parseEther('6');
const kink1 = utils.parseEther('0.79');
const roof = utils.parseEther('2');

export default {
  baseRate,
  multiplier,
  jumpMultiplier,
  kink1,
  roof,
};
