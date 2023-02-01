import { ethers, upgrades } from "hardhat";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../../constant";
import { SoftVault } from "../../typechain-types";
import { deployment, writeDeployments } from '../../utils';

async function main(): Promise<void> {
	const [deployer] = await ethers.getSigners();
	console.log("Deployer:", deployer.address);

	// // Protocol Config
	// const ProtocolConfig = await ethers.getContractFactory(CONTRACT_NAMES.ProtocolConfig);
	// const config = await upgrades.deployProxy(ProtocolConfig, [
	// 	deployer.address
	// ]);
	// console.log('Protocol Config:', config.address);
	// deployment.ProtocolConfig = config.address;
	// writeDeployments(deployment);

	// SoftVault
	const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
	const vault = <SoftVault>await upgrades.deployProxy(SoftVault, [
		deployment.ProtocolConfig,
		ADDRESS_GOERLI.bICHI,
		"Interest Bearing ICHI",
		"ibICHI"
	]);
	await vault.deployed();
	console.log('Soft Vault-ICHI:', vault.address);
	deployment.SoftVault_ICHI = vault.address;
	writeDeployments(deployment);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
