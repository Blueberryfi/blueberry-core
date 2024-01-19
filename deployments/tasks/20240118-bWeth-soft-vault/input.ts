import { utils } from 'ethers';
import Task, { TaskMode } from 'task';

export type SoftVaultDeployment = {
  WETH: string;
  Comptroller: string;
  JumpRateModelV2: string;
  tokenName: string;
  tokenSymbol: string;
  bTokenDecimals: number;
  BTokenAdmin: string;
  ProtocolConfig: string;
  vaultName: string;
  vaultSymbol: string;
  Owner: string;
  initialExchangeRateMantissa: string;
};

const BTokenAdmin = new Task('20240118-bToken-admin', TaskMode.READ_ONLY);
const JumpRateModelV2 = new Task('20240118-jump-rate-model-v2', TaskMode.READ_ONLY);
const Comptroller = new Task('20240118-comptroller', TaskMode.READ_ONLY);
const WETH = new Task('00000000-constants', TaskMode.READ_ONLY);
const ProtocolConfig = new Task('20240118-protocol-config', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

const tokenName = 'Blueberry Wrapped ETH';
const tokenSymbol = 'bWETH';

const vaultName = 'Interest Bearing WETH';
const vaultSymbol = 'ibWETH';

const underlyingTokenDecimals = 18;
const bTokenDecimals = 18;

const initialExchangeRateMantissa = utils.parseUnits('0.01', 18 + underlyingTokenDecimals - bTokenDecimals);

export default {
  WETH,
  Comptroller,
  JumpRateModelV2,
  tokenName,
  tokenSymbol,
  bTokenDecimals,
  BTokenAdmin,
  ProtocolConfig,
  vaultName,
  vaultSymbol,
  Owner,
  initialExchangeRateMantissa,
};
