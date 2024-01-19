import Task, { TaskMode } from "task";

export type ConvexSpellDeployment = {
  BlueberryBank: string;
  WERC20: string;
  WETH: string;
  WConvexBooster: string;
  CurveStableOracle: string;
  CurveTricryptoOracle: string;
  CurveVolatileOracle: string;
  AugustusSwapper: string;
  TokenTransferProxy: string;
  Owner: string;
};

const BlueberryBank = new Task('20240118-blueberry-bank', TaskMode.READ_ONLY);
const WERC20 = new Task('20240118-wErc20', TaskMode.READ_ONLY);
const WETH = new Task('00000000-constants', TaskMode.READ_ONLY);
const WConvexBooster = new Task('20240118-wConvex-booster', TaskMode.READ_ONLY);
const CurveStableOracle = new Task('20240118-curve-stable-oracle', TaskMode.READ_ONLY);
const CurveTricryptoOracle = new Task('20240118-curve-tricrypto-oracle', TaskMode.READ_ONLY);
const CurveVolatileOracle = new Task('20240118-curve-volatile-oracle', TaskMode.READ_ONLY);
const AugustusSwapper = new Task('00000000-constants', TaskMode.READ_ONLY);
const TokenTransferProxy = new Task('00000000-constants', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

export default {
  BlueberryBank,
  WERC20,
  WETH,
  WConvexBooster,
  CurveStableOracle,
  CurveTricryptoOracle,
  CurveVolatileOracle,
  AugustusSwapper,
  TokenTransferProxy,
  Owner,
};
