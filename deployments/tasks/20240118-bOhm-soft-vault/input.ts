import { utils } from 'ethers';
import Task, { TaskMode } from 'task';

export type SoftVaultDeployment = {
  OHM: string;
  Comptroller: string;
  JumpRateModelV2: string;
  tokenName: string;
  tokenSymbol: string;
  bTokenDecimals: number;
  BTokenAdmin: string;
  ProtcolConfig: string;
  vaultName: string;
  vaultSymbol: string;
  Owner: string;
  initialExchangeRateMantissa: string;
};

const BTokenAdmin = new Task('20240118-bToken-admin', TaskMode.READ_ONLY);
const JumpRateModelV2 = new Task('20240118-jump-rate-model-v2', TaskMode.READ_ONLY);
const Comptroller = new Task('20240118-comptroller', TaskMode.READ_ONLY);
const OHM = new Task('00000000-constants', TaskMode.READ_ONLY);
const ProtcolConfig = new Task('20240118-protocol-config', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constants', TaskMode.READ_ONLY);

const tokenName = 'Blueberry Wrapped OHM';
const tokenSymbol = 'bOHM';

const vaultName = 'Interest Bearing OHM';
const vaultSymbol = 'ibOHM';

const underlyingTokenDecimals = 9;
const bTokenDecimals = 18;

const initialExchangeRateMantissa = utils.parseUnits('0.01', 18 + underlyingTokenDecimals - bTokenDecimals);

export default {
  OHM,
  Comptroller,
  JumpRateModelV2,
  tokenName,
  tokenSymbol,
  bTokenDecimals,
  BTokenAdmin,
  ProtcolConfig,
  vaultName,
  vaultSymbol,
  Owner,
  initialExchangeRateMantissa,
};
