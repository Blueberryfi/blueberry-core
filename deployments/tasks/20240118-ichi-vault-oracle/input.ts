import Task, { TaskMode } from "task";

export type IchiVaultOracleDeployment = {
  CoreOracle: string;
  owner: string;
};

const CoreOracle = new Task('20240118-core-oracle', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  CoreOracle,
  Owner,
};
