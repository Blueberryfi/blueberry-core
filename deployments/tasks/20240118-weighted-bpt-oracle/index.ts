import { Task, TaskRunOptions } from '@src';
import { WeightedBPTOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as WeightedBPTOracleDeployment;
  const args = [input.balancerVault, input.coreOracle, input.owner];
  await task.deployAndVerifyProxy('WeightedBPTOracle', args, from, force);
};
