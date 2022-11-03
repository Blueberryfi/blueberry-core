import { utils } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS_GOERLI, CONTRACT_NAMES } from '../../../constant';
import SpellABI from '../../../abi/IchiVaultSpell.json';

async function main(): Promise<void> {
	const iface = new ethers.utils.Interface(SpellABI);
	const banka = await ethers.getContractAt(CONTRACT_NAMES.BlueBerryBank, '0x466F1FD0662aae5e3ec7f706A54E623381fC2D2d')
	// const usdc = await ethers.getContractAt(CONTRACT_NAMES.IERC20, ADDRESS_GOERLI.SupplyToken);
	// await usdc.approve(banka.address, ethers.constants.MaxUint256);
	console.log(iface.encodeFunctionData("deposit", [
		ADDRESS_GOERLI.SupplyToken,
		utils.parseUnits('100', 18),
		utils.parseUnits('200', 18)
	]));
	await banka.execute(
		0,
		'0x579a39219CF6258a043Af80d09ddcfA6ae9160E2',
		iface.encodeFunctionData("deposit", [
			ADDRESS_GOERLI.SupplyToken,
			utils.parseUnits('100', 18),
			utils.parseUnits('200', 18)
		])
	)
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
