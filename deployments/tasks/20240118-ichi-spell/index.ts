import { Task, TaskRunOptions } from '@src';
import { IchiSpellDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as IchiSpellDeployment;
  const args = [input.bank, input.werc20, input.weth, input.wIchiFarm, input.uniV3Router, input.augustusSwapper, input.tokenTransferProxy, input.owner];
  await task.deployAndVerifyProxy('IchiSpell', args, from, force);
};
