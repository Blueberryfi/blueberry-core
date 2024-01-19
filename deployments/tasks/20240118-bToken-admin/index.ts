import { Task, TaskRunOptions } from '@src';
import { BTokenAdminDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as BTokenAdminDeployment;
  const args = [input.Owner];
  await task.deployAndVerify('BTokenAdmin', args, from, force);
};
