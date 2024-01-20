import { Task, TaskRunOptions } from '@src';
import { ChainlinkAdapterOracleDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as ChainlinkAdapterOracleDeployment;

  const args = [input.ChainlinkFeed, input.Owner];

  /// Deploy volatile curve spell
  await task.deployAndVerifyProxy('ChainlinkAdapterOracle', args, from, force);
};
