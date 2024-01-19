import { Task, TaskRunOptions } from '@src';
import { ProtocolConfigDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as ProtocolConfigDeployment;
  const args = ['0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7', '0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7'];
  await task.deployAndVerifyProxy('ProtocolConfig', args, from, force);
};
