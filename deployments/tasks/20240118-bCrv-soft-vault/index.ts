import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bCRVDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bCRVDelegatorArgs = [
    input.CRV,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bCRVDelegate.address,
    '0x00',
  ];
  const bCRVDelegator = await task.deployAndVerify('BErc20Delegator', bCRVDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bCRVDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
