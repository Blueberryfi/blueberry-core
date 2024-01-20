import Task, { TaskMode } from "task";

export type IchiSpellDeployment = {
  BlueberryBank: string;
  WERC20: string;
  WETH: string;
  AugustusSwapper: string;
  TokenTransferProxy: string;
  Owner: string;
};

const BlueberryBank = new Task('20240118-blueberry-bank', TaskMode.READ_ONLY);
const WERC20 = new Task('20240118-wErc20', TaskMode.READ_ONLY);
const WETH = new Task('00000000-constants', TaskMode.READ_ONLY);
const AugustusSwapper = new Task('00000000-constants', TaskMode.READ_ONLY);
const TokenTransferProxy = new Task('00000000-constants', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);
0
export default {
  BlueberryBank,
  WERC20,
  WETH,
  AugustusSwapper,
  TokenTransferProxy,
  Owner,
};
