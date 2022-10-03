import { ethers, upgrades } from "hardhat";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../../../constants";
import { BlueBerryBank, SafeBox } from "../../../typechain-types";

async function main(): Promise<void> {
	const Bank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
	const bank = <BlueBerryBank>await upgrades.upgradeProxy('0x466F1FD0662aae5e3ec7f706A54E623381fC2D2d', Bank, {
		unsafeAllow: ["delegatecall"]
	});
	await bank.deployed();

	await bank.updateSafeBox(ADDRESS_GOERLI.SupplyToken, '0x214b2Fab2541c9cA8B206e6E3B07fa5c6b7731Bf');
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
