import { Task, TaskRunOptions } from '@src';
import { AggregatorOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as AggregatorOracleDeployment;
  const args = [input.Owner];
  await task.deployAndVerifyProxy('AggregatorOracle', args, from, force);
};
