import { Task, TaskRunOptions } from '@src';
import { CoreOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as CoreOracleDeployment;

  const args = [input.Owner];

  /// Deploy volatile curve spell
  await task.deployAndVerifyProxy('CoreOracle', args, from, force);
};