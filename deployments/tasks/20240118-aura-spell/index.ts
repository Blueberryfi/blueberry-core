import { Task, TaskRunOptions } from '@src';
import { AuraSpellDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as AuraSpellDeployment;
  const args = [input.BlueberryBank, input.WERC20, input.WETH, input.WAuraBooster, input.AugustusSwapper, input.TokenTransferProxy, input.Owner];

  await task.deployAndVerifyProxy('AuraSpell', args, from, force);
};
