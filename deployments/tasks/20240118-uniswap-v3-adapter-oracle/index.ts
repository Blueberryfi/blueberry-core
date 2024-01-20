import { Task, TaskRunOptions } from '@src';
import { UniswapV3AdapterOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as UniswapV3AdapterOracleDeployment;
  const args = [input.CoreOracle, input.Owner];
  const lib = { UniV3WrappedLibContainer: input.UniV3WrappedLibContainer };
  
  await task.deployAndVerifyProxy('UniswapV3AdapterOracle', args, from, force, lib);
};
