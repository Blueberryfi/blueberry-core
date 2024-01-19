import { Task, TaskRunOptions } from '@src';
import { CurveStableOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as CurveStableOracleDeployment;
  const args = [input.CrvAddressProvider, input.CoreOracle, input.Owner];
  await task.deployAndVerifyProxy('CurveStableOracle', args, from, force);
};
