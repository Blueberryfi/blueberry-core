import { Task, TaskRunOptions } from '@src';
import { ConvexSpellDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as ConvexSpellDeployment;

  const stableArgs = [
    input.BlueberryBank,
    input.WERC20,
    input.WETH,
    input.WConvexBooster,
    input.CurveStableOracle,
    input.AugustusSwapper,
    input.TokenTransferProxy,
    input.Owner
  ];

  const tricryptoArgs = [
    input.BlueberryBank,
    input.WERC20,
    input.WETH,
    input.WConvexBooster,
    input.CurveTricryptoOracle,
    input.AugustusSwapper,
    input.TokenTransferProxy,
    input.Owner
  ];

  const volatileArgs = [
    input.BlueberryBank,
    input.WERC20,
    input.WETH,
    input.WConvexBooster,
    input.CurveVolatileOracle,
    input.AugustusSwapper,
    input.TokenTransferProxy,
    input.Owner
  ];

  /// Deploy stable curve spell
  await task.deployAndVerifyProxy('ConvexSpell', stableArgs, from, force);

  /// Deploy tricrypto curve spell
  await task.deployAndVerifyProxy('ConvexSpell', tricryptoArgs, from, force);

  /// Deploy volatile curve spell
  await task.deployAndVerifyProxy('ConvexSpell', volatileArgs, from, force);
};
