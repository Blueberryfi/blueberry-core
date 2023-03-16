import { ethers } from "hardhat";
import { CONTRACT_NAMES } from "../../constant";
import { IchiVaultOracle } from "../../typechain-types";
import { deployment, writeDeployments } from "../../utils";

async function main(): Promise<void> {
	const [deployer] = await ethers.getSigners();
	console.log("Deployer:", deployer.address);

	// Ichi Lp Oracle
	const IchiVaultOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultOracle);
	const ichiVaultOracle = <IchiVaultOracle>await IchiVaultOracle.deploy(deployment.CoreOracle);
	await ichiVaultOracle.deployed();
	console.log('Ichi Lp Oracle Address:', ichiVaultOracle.address);
	deployment.IchiVaultOracle = ichiVaultOracle.address;
	writeDeployments(deployment);

	// const coreOracle = await ethers.getContractAt("CoreOracle", deployment.CoreOracle);
	// await coreOracle.setTokenSettings(
	// 	[deployment.MockIchiVault],
	// 	[{
	// 		liqThreshold: 10000,
	// 		route: deployment.IchiVaultOracle,
	// 	}]
	// );
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
