import fs from 'fs';
import { ethers, network, upgrades } from "hardhat";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../../constant";
import { SafeBox } from "../../typechain-types";

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

	// // Protocol Config
	// const ProtocolConfig = await ethers.getContractFactory("ProtocolConfig");
	// const config = await upgrades.deployProxy(ProtocolConfig, [
	// 	deployer.address
	// ]);
	// console.log('Protocol Config:', config.address);
	// deployment.ProtocolConfig = config.address;
	// writeDeployments(deployment);

	// SafeBox
	const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
	const safeBox = <SafeBox>await upgrades.deployProxy(SafeBox, [
		deployment.ProtocolConfig,
		ADDRESS_GOERLI.bWETH,
		"Interest Bearing WETH",
		"ibWETH"
	]);
	await safeBox.deployed();
	console.log('SafeBox-WETH:', safeBox.address);
	deployment.SafeBox_WETH = safeBox.address;
	writeDeployments(deployment);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
