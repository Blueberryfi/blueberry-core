import { utils } from 'ethers';
import fs from 'fs';
import { ethers, network, upgrades } from "hardhat";
import { } from "../../constant";
import { MockERC20 } from "../../typechain-types";

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

	// Deploy Mock Token
	const MockERC20 = await ethers.getContractFactory("MockERC20");
	const mock = await MockERC20.deploy("Mock BAL", "BAL", 18);
	await mock.deployed();

	deployment.MockBAL = mock.address;
	writeDeployments(deployment);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
