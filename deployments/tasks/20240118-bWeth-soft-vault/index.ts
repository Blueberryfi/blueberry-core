import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bwBTCDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bwBTCDelegatorArgs = [
    input.WETH,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bwBTCDelegate.address,
    '0x00',
  ];
  const bwBTCDelegator = await task.deployAndVerify('BErc20Delegator', bwBTCDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bwBTCDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
