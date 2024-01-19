import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bOHMDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bOHMDelegatorArgs = [
    input.OHM,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bOHMDelegate.address,
    '0x00',
  ];
  const bOHMDelegator = await task.deployAndVerify('BErc20Delegator', bOHMDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtcolConfig, bOHMDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
