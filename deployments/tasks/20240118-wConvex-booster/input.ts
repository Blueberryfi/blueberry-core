import Task, { TaskMode } from "task";

export type WConvexBoosterDeployment = {
  CVX: string;
  CvxBooster: string;
  PoolEscrowFactory: string;
  Owner: string;
};

const CVX = new Task('00000000-constants', TaskMode.READ_ONLY);
const CvxBooster = new Task('00000000-constants', TaskMode.READ_ONLY);
const PoolEscrowFactory = new Task('20240118-pool-escrow', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  CVX,
  CvxBooster,
  PoolEscrowFactory,
  Owner,
};

