import { Task, TaskRunOptions } from '@src';
import { WERC20Deployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as WERC20Deployment;
  const args = [input.Owner];
  await task.deployAndVerifyProxy('WERC20', args, from, force);
};
