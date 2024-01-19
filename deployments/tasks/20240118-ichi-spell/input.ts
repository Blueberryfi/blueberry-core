import Task, { TaskMode } from "task";

export type IchiSpellDeployment = {
  bank: string;
  werc20: string;
  weth: string;
  wIchiFarm: string;
  uniV3Router: string;
  augustusSwapper: string;
  tokenTransferProxy: string;
  owner: string;
};

const Bank = new Task('20240118-blueberry-bank', TaskMode.READ_ONLY);
const WERC20 = new Task('20240118-wErc20', TaskMode.READ_ONLY);
const WETH = new Task('00000000-constants', TaskMode.READ_ONLY);
const WIchiFarm = new Task('20240118-wIchi-farm', TaskMode.READ_ONLY);
const UniV3Router = new Task('20240118-uni-v3-router', TaskMode.READ_ONLY);
const AugustusSwapper = new Task('00000000-constants', TaskMode.READ_ONLY);
const TokenTransferProxy = new Task('00000000-constants', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);
0
export default {
  Bank,
  WERC20,
  WETH,
  WIchiFarm,
  UniV3Router,
  AugustusSwapper,
  TokenTransferProxy,
  Owner,
};
