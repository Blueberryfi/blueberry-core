import Task, { TaskMode } from "task";

export type ChainlinkAdapterOracleDeployment = {
  chainlinkFeed: string;
  Owner: string;
};

const ChainlinkFeed = '0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf';
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  ChainlinkFeed,
  Owner,
};
