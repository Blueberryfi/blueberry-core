import fs from 'fs';
import { ethers, network, upgrades } from "hardhat";
import { CONTRACT_NAMES } from "../../constant";
import { IchiVaultSpell } from "../../typechain-types";

const deploymentPath = "./deployments";
const deploymentFilePath = `${deploymentPath}/${network.name}.json`;

async function main(): Promise<void> {
	const deployment = fs.existsSync(deploymentFilePath)
		? JSON.parse(fs.readFileSync(deploymentFilePath).toString())
		: {};

	const [deployer] = await ethers.getSigners();
	console.log("Deployer:", deployer.address);

	const IchiVaultSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);
	const ichiSpell = <IchiVaultSpell>await upgrades.upgradeProxy(deployment.IchiSpell, IchiVaultSpell);
	await ichiSpell.deployed();

	console.log("Ichi Vault Spell Upgraded");

	await ichiSpell.setBank(deployment.BlueBerryBank);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
