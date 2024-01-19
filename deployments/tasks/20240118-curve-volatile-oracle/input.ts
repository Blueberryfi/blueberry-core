import Task, { TaskMode } from "task";

export type CurveVolatileOracleDeployment = {
  CrvAddressProvider: string;
  CoreOracle: string;
  Owner: string;
};

const CrvAddressProvider = '0x0000000022d53366457f9d5e68ec105046fc4383';
const CoreOracle = new Task('20240118-core-oracle', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  CrvAddressProvider,
  CoreOracle,
  Owner,
};
