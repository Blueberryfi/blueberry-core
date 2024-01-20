import { Task, TaskRunOptions } from '@src';
import { IchiSpellDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as IchiSpellDeployment;
  const args = [input.BlueberryBank, input.WERC20, input.WETH, input.AugustusSwapper, input.TokenTransferProxy, input.Owner];
  await task.deployAndVerifyProxy('IchiSpell', args, from, force);
};
