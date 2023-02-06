import { ethers, upgrades } from "hardhat";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../../constant";
import { IchiVaultSpell } from "../../typechain-types";
import { deployment, writeDeployments } from '../../utils';

async function main(): Promise<void> {
	const [deployer] = await ethers.getSigners();
	console.log("Deployer:", deployer.address);

	const IchiVaultSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);

	const spell = <IchiVaultSpell>await upgrades.deployProxy(IchiVaultSpell, [
		deployment.BlueBerryBank,
		deployment.WERC20,
		ADDRESS_GOERLI.WETH,
		deployment.WIchiFarm
	])
	await spell.deployed();
	console.log("Ichi Vault Spell Deployed:", spell.address);
	deployment.IchiSpell = spell.address;
	writeDeployments(deployment)
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
