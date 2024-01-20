import { Task, TaskRunOptions } from '@src';
import { IchiVaultOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as IchiVaultOracleDeployment;
  const args = [input.CoreOracle, input.Owner];
  const lib = { UniV3WrappedLibContainer: input.UniV3WrappedLibContainer };
  
  await task.deployAndVerifyProxy('IchiVaultOracle', args, from, force, lib);
};
