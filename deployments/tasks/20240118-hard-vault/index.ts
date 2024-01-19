import { Task, TaskRunOptions } from '@src';
import { HardVaultDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as HardVaultDeployment;
  const args = [input.ProtocolConfig, input.Owner];
  await task.deployAndVerifyProxy('HardVault', args, from, force);
};
