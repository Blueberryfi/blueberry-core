import { Libraries } from "hardhat/types";
import Task, { TaskMode } from "task";

export type IchiVaultOracleDeployment = {
  CoreOracle: string;
  Owner: string;
  UniV3WrappedLibContainer: string
};

const CoreOracle = new Task('20240118-core-oracle', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);
const UniV3WrappedLibContainer = new Task('20240118-uni-v3-wrapped-lib-container', TaskMode.READ_ONLY);

export default {
  CoreOracle,
  Owner,
  UniV3WrappedLibContainer
};
