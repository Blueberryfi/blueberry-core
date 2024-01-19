import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bALCXDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bALCXDelegatorArgs = [
    input.ALCX,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bALCXDelegate.address,
    '0x00',
  ];
  const bALCXDelegator = await task.deployAndVerify('BErc20Delegator', bALCXDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bALCXDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
