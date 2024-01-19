import Task, { TaskMode } from "task";

export type UniswapV2OracleDeployment = {
  CoreOracle: string;
  Owner: string;
};

const CoreOracle = new Task('20240118-core-oracle', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  CoreOracle,
  Owner,
};
