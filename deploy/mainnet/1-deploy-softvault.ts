import fs from 'fs';
import { ethers, network, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { SoftVault } from '../../typechain-types';

const deploymentPath = "./deployments";
const deploymentFilePath = `${deploymentPath}/${network.name}.json`;

function writeDeployments(deployment: any) {
	if (!fs.existsSync(deploymentPath)) {
		fs.mkdirSync(deploymentPath);
	}
	fs.writeFileSync(deploymentFilePath, JSON.stringify(deployment, null, 2));
}

async function main(): Promise<void> {
	const deployment = fs.existsSync(deploymentFilePath)
		? JSON.parse(fs.readFileSync(deploymentFilePath).toString())
		: {};

	const [deployer] = await ethers.getSigners();
	console.log("Deployer:", deployer.address);

	// // Deploy Config
	// const Config = await ethers.getContractFactory("ProtocolConfig");
	// const config = await upgrades.deployProxy(Config, ["0xE4D701c6E3bFbA3e50D1045A3cef4797b6165119"])
	// await config.deployed();
	// console.log("ProtocolConfig deployed at:", config.address);
	// deployment.ProtocolConfig = config.address;
	// writeDeployments(deployment);

	const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);

	// Deploy USDC SoftVault
	const softVault = <SoftVault>await upgrades.deployProxy(SoftVault, [
		deployment.ProtocolConfig,
		ADDRESS.bWETH,
		"Interest Bearing WETH",
		"ibWETH",
	])
	await softVault.deployed();
	console.log(softVault.address);
	deployment.SoftVault_WETH = softVault.address;
	writeDeployments(deployment);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
