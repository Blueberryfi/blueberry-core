import { Task, TaskMode, TaskRunOptions } from '@src';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  await task.deployAndVerify('Comptroller', [], from, force);
};
