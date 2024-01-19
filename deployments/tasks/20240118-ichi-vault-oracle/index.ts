import { Task, TaskRunOptions } from '@src';
import { IchiVaultOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as IchiVaultOracleDeployment;
  const args = [input.CoreOracle, input.owner];

  const UniswapV3WrappedLibContainer = await task.deployAndVerify('UniswapV3WrappedLibContainer', [], from, force);

  await task.deployAndVerifyProxy('IchiVaultOracle', args, from, force, UniswapV3WrappedLibContainer);
};
