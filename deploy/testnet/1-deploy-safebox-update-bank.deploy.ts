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

	// SafeBox
	const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
	const safeBox = <SafeBox>await upgrades.deployProxy(SafeBox, [
		ADDRESS_GOERLI.bUSDC,
		"Interest Bearing USDC",
		"ibUSDC"
	]);
	await safeBox.deployed();
	console.log('SafeBox-USDC:', safeBox.address);
	deployment.USDC_SafeBox = safeBox.address;
	writeDeployments(deployment);

	await safeBox.setBank(deployment.BlueBerryBank);

	const bank = await ethers.getContractAt("BlueBerryBank", deployment.BlueBerryBank);
	await bank.updateSafeBox(deployment.MockUSDC, deployment.USDC_SafeBox);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
