import Task, { TaskMode } from 'task';

export type ChainlinkAdapterOracleDeployment = {
  ChainlinkFeed: string;
  Owner: string;
};

const ChainlinkFeed = new Task('00000000-constants', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  ChainlinkFeed,
  Owner,
};
