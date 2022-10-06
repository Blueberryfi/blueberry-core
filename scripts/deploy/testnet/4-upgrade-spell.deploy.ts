import { ethers } from "hardhat";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../../../constants";
import { BlueBerryBank, IchiVaultSpell } from "../../../typechain-types";
import SpellABI from '../../../abi/IchiVaultSpell.json';
import { utils } from "ethers";

async function main(): Promise<void> {
	// const iface = new ethers.utils.Interface(SpellABI);
	// console.log(iface.encodeFunctionData("increasePosition", [
	// 	'0xEdA174a7DcC44CC391C21cCFd16715eE660Bd35f',
	// 	utils.parseUnits('100', 18),
	// ]))
	// return;

	const IchiVaultSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);
	const spell = <IchiVaultSpell>await IchiVaultSpell.deploy(
		'0x466F1FD0662aae5e3ec7f706A54E623381fC2D2d',
		'0x6c73798750F4a46B7C6a8296830c931a765Dd50a',
		ADDRESS_GOERLI.WETH,
		'0x1c8E8C7486F5726EF7436e78B910897aBeB3Fb4f'
	)
	await spell.deployed();
	console.log('Spell:', spell.address);

	const bank = <BlueBerryBank>await ethers.getContractAt(CONTRACT_NAMES.BlueBerryBank, '0x466F1FD0662aae5e3ec7f706A54E623381fC2D2d');
	await bank.setWhitelistSpells([
		'0x579a39219CF6258a043Af80d09ddcfA6ae9160E2',
		spell.address
	], [false, true]);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
