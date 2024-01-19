import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bMIMDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bMIMDelegatorArgs = [
    input.MIM,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bMIMDelegate.address,
    '0x00',
  ];
  const bMIMDelegator = await task.deployAndVerify('BErc20Delegator', bMIMDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bMIMDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
