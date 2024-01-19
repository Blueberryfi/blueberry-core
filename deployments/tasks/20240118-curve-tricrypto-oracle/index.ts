import { Task, TaskRunOptions } from '@src';
import { CurveTricryptoOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as CurveTricryptoOracleDeployment;
  const args = [input.CrvAddressProvider, input.CoreOracle, input.Owner];
  await task.deployAndVerifyProxy('CurveTricryptoOracle', args, from, force);
};
