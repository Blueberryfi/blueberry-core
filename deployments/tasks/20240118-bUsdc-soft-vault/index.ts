import { Task, TaskRunOptions } from '@src';
import { SoftVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as SoftVaultDeployment;
  const bUSDCDelegate = await task.deployAndVerify('BCollateralCapErc20Delegate', [], from, force);
  const bUSDCDelegatorArgs = [
    input.USDC,
    input.Comptroller,
    input.JumpRateModelV2,
    input.initialExchangeRateMantissa,
    input.tokenName,
    input.tokenSymbol,
    input.bTokenDecimals,
    input.BTokenAdmin,
    bUSDCDelegate.address,
    '0x00',
  ];
  const bUSDCDelegator = await task.deployAndVerify('BErc20Delegator', bUSDCDelegatorArgs, from, force);
  const softVaultArgs = [input.ProtocolConfig, bUSDCDelegator.address, input.vaultName, input.vaultSymbol, input.Owner];
  await task.deployAndVerifyProxy('SoftVault', softVaultArgs, from, force);
};
