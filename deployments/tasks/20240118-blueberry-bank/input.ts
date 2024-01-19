import Task, { TaskMode } from "task";

export type BlueberryBankDeployment = {
  CoreOracle: string;
  ProtocolConfig: string;
  Owner: string;
};

const CoreOracle = new Task('20240118-core-oracle', TaskMode.READ_ONLY);
const ProtocolConfig = new Task('20240118-protocol-config', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  CoreOracle,
  ProtocolConfig,
  Owner,
};
