import { Task, TaskRunOptions } from '@src';
import {FeeManagerDeployment} from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as FeeManagerDeployment;

  const args = [input.protocolConfig, input.owner];

  await task.deployAndVerify('FeeManager', args, from, force);
};
