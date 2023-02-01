import { ethers } from "hardhat";
import { CONTRACT_NAMES } from "../../constant";
import { IchiLpOracle } from "../../typechain-types";
import { deployment, writeDeployments } from "../../utils";

async function main(): Promise<void> {
	const [deployer] = await ethers.getSigners();
	console.log("Deployer:", deployer.address);

	// Ichi Lp Oracle
	const IchiLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiLpOracle);
	const ichiLpOracle = <IchiLpOracle>await IchiLpOracle.deploy(deployment.CoreOracle);
	await ichiLpOracle.deployed();
	console.log('Ichi Lp Oracle Address:', ichiLpOracle.address);
	deployment.IchiLpOracle = ichiLpOracle.address;
	writeDeployments(deployment);

	// const coreOracle = await ethers.getContractAt("CoreOracle", deployment.CoreOracle);
	// await coreOracle.setTokenSettings(
	// 	[deployment.MockIchiVault],
	// 	[{
	// 		liqThreshold: 10000,
	// 		route: deployment.IchiLpOracle,
	// 	}]
	// );
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
