import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bwETHDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bwETHDelegatorArgs = [
    input.WBTC,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bwETHDelegate.address,
    '0x00',
  ];
  const bwETHDelegator = await task.deployAndVerify('BErc20Delegator', bwETHDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bwETHDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
