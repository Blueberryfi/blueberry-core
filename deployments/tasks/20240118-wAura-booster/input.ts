import Task, { TaskMode } from "task";

export type WAuraBoosterDeployment = {
  AURA: string;
  AuraBooster: string;
  PoolEscrowFactory: string;
  BalancerVault: string;
  Owner: string;
};

const AURA = new Task('00000000-constants', TaskMode.READ_ONLY);
const AuraBooster = new Task('00000000-constants', TaskMode.READ_ONLY);
const PoolEscrowFactory = new Task('20240118-pool-escrow', TaskMode.READ_ONLY);
const BalancerVault = new Task('00000000-constants', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  AURA,
  AuraBooster,
  PoolEscrowFactory,
  BalancerVault,
  Owner,
};

