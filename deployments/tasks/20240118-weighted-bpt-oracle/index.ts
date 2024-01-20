import { Task, TaskRunOptions } from '@src';
import { WeightedBPTOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as WeightedBPTOracleDeployment;
  const args = [input.BalancerVault, input.CoreOracle, input.Owner];
  await task.deployAndVerifyProxy('WeightedBPTOracle', args, from, force);
};
