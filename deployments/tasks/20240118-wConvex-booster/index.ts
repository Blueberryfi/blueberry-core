import { Task, TaskRunOptions } from '@src';
import { WConvexBoosterDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as WConvexBoosterDeployment;
  const args = [
    input.CVX,
    input.CvxBooster,
    input.PoolEscrowFactory,
    input.Owner
  ];
  await task.deployAndVerifyProxy('WConvexBooster', args, from, force);
};
