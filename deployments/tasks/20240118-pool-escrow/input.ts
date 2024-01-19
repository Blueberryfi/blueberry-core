import Task, { TaskMode } from "task";

export type PoolEscrowFactoryDeployment = {
  Owner: string;
};

const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  Owner,
};
