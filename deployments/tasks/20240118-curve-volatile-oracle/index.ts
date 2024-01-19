import { Task, TaskRunOptions } from '@src';
import { CurveVolatileOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as CurveVolatileOracleDeployment;
  const args = [input.CrvAddressProvider, input.CoreOracle, input.Owner];
  await task.deployAndVerifyProxy('CurveVolatileOracle', args, from, force);
};
