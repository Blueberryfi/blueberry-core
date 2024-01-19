import Task, { TaskMode } from "task";

export type WIchiFarmDeployment = {
  ICHI: string;
  ICHIV1: string;
  IchiFarm: string;
  Owner: string;
};

const ICHI = new Task('00000000-constant', TaskMode.READ_ONLY);
const ICHIV1 = new Task('00000000-constant', TaskMode.READ_ONLY);
const IchiFarm = new Task('00000000-constant', TaskMode.READ_ONLY);
const Owner = new Task('00000000-constant', TaskMode.READ_ONLY);

export default {
  ICHI,
  ICHIV1,
  IchiFarm,
  Owner,
};
