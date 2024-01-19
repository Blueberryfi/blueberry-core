import { Task, TaskRunOptions } from '@src';
import { UniswapV2OracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as UniswapV2OracleDeployment;
  const args = [input.CoreOracle, input.Owner];
  await task.deployAndVerifyProxy('UniswapV2Oracle', args, from, force);
};
