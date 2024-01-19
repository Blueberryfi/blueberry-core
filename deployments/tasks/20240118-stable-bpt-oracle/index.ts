import { Task, TaskRunOptions } from '@src';
import { StableBPTOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as StableBPTOracleDeployment;
  const args = [input.balancerVault, input.coreOracle, input.owner];
  await task.deployAndVerifyProxy('StableBPTOracle', args, from, force);
};
