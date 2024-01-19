import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bBALDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bBALDelegatorArgs = [
    input.BAL,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bBALDelegate.address,
    '0x00',
  ];
  const bBALDelegator = await task.deployAndVerify('BErc20Delegator', bBALDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bBALDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
