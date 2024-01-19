import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bLINKDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bLINKDelegatorArgs = [
    input.LINK,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bLINKDelegate.address,
    '0x00',
  ];
  const bLINKDelegator = await task.deployAndVerify('BErc20Delegator', bLINKDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bLINKDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
