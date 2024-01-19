import { Task, TaskRunOptions } from '@src';
import { HardVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as HardVaultDeployment;

  const args = [input.baseRate, input.multiplier, input.jumpMultiplier, input.kink1, input.roof];
  await task.deploy('JumpRateModelV2', args, from, force);
};
