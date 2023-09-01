import fs from 'fs';
import { ethers, network, upgrades } from "hardhat";
import { CONTRACT_NAMES } from '../../constant';
import { SoftVault } from "../../typechain-types";

const deploymentPath = "./deployments";
const deploymentFilePath = `${deploymentPath}/${network.name}.json`;

async function main(): Promise<void> {
	const deployment = fs.existsSync(deploymentFilePath)
		? JSON.parse(fs.readFileSync(deploymentFilePath).toString())
		: {};

	const [deployer] = await ethers.getSigners();
	console.log("Deployer:", deployer.address);

	// SoftVault
	const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
	let safeBox = <SoftVault>await upgrades.upgradeProxy(deployment.USDC_SafeBox, SoftVault);
	await safeBox.deployed();

	safeBox = <SoftVault>await upgrades.upgradeProxy(deployment.ICHI_SafeBox, SoftVault);
	await safeBox.deployed();
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
