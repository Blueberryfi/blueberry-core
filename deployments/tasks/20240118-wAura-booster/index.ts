import { Task, TaskRunOptions } from '@src';
import { WAuraBoosterDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as WAuraBoosterDeployment;

  const args = [
    input.AURA,
    input.AuraBooster,
    input.PoolEscrowFactory,
    input.BalancerVault,
    input.Owner
  ];

  await task.deployAndVerifyProxy('WAuraBooster', args, from, force);
};
