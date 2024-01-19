import Task, { TaskMode } from "task";

export type WeightedBPTOracleDeployment = {
  balancerVault: string;
  coreOracle: string;
  owner: string;
};

const BalancerVault = new Task('00000000-constants', TaskMode.READ_ONLY);
const CoreOracle = new Task('20240118-core-oracle', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  BalancerVault,
  CoreOracle,
  Owner,
};
