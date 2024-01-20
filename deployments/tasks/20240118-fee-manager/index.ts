import { Task, TaskRunOptions } from '@src';
import { FeeManagerDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as FeeManagerDeployment;

  const args = [input.ProtocolConfig, input.Owner];

  await task.deployAndVerifyProxy('FeeManager', args, from, force);
};
