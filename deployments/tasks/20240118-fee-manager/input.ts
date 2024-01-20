import Task, { TaskMode } from 'task';

export type FeeManagerDeployment = {
  ProtocolConfig: string;
  Owner: string;
};

const ProtocolConfig = new Task('20240118-protocol-config', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  ProtocolConfig,
  Owner,
};
