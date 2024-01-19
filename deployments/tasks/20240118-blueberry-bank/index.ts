import { Task, TaskRunOptions } from '@src';
import { BlueberryBankDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as BlueberryBankDeployment;
  const args = [input.CoreOracle, input.ProtocolConfig, input.Owner];
  await task.deployAndVerifyProxy('BlueberryBank', args, from, force);
};
