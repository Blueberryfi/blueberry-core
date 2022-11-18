import fs from 'fs';
import { ethers, network } from "hardhat";
import { CONTRACT_NAMES } from "../../../constant";
import { IchiLpOracle } from "../../../typechain-types";

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

	// Ichi Lp Oracle
	const IchiLpOracle = await ethers.getContractFactory("IchiLpOracle");
	const ichiLpOracle = <IchiLpOracle>await IchiLpOracle.deploy(deployment.CoreOracle);
	await ichiLpOracle.deployed();
	console.log('Ichi Lp Oracle Address:', ichiLpOracle.address);
	deployment.IchiLpOracle = ichiLpOracle.address;
	writeDeployments(deployment);

	const coreOracle = await ethers.getContractAt("CoreOracle", deployment.CoreOracle);
	await coreOracle.setTokenSettings(
		[deployment.MockIchiVault],
		[{
			liqThreshold: 10000,
			route: deployment.IchiLpOracle,
		}]
	);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
