import { Task, TaskRunOptions } from '@src';
import { WIchiFarmDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as WIchiFarmDeployment;
  const args = [input.ICHI, input.ICHIV1, input.IchiFarm, input.Owner];
  await task.deployAndVerifyProxy('WIchiFarm', args, from, force);
};
