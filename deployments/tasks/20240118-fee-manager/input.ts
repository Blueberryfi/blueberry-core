import Task, { TaskMode } from 'task';

export type FeeManagerDeployment = {
  protocolConfig: string;
  owner: string;
};

const ProtocolConfig = new Task('202404118-fee-manager', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  ProtocolConfig,
  Owner,
};
