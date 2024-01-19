import { Task, TaskRunOptions } from '@src';
import { PoolEscrowFactoryDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as PoolEscrowFactoryDeployment;
  const args = [input.Owner];

  await task.deployAndVerifyProxy('PoolEscrowFactory', args, from, force);
};
