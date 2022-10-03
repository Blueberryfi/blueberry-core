import { ethers } from "hardhat";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../../../constants";
import { SafeBox } from "../../../typechain-types";

async function main(): Promise<void> {
	const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
	const safeBox = <SafeBox>await SafeBox.deploy(
		ADDRESS_GOERLI.bSupplyToken,
		"Interest Bearing USDC",
		"ibUSDC"
	)
	await safeBox.deployed();
	console.log('SafeBox:', safeBox.address);
	await safeBox.setBank('0x466F1FD0662aae5e3ec7f706A54E623381fC2D2d');
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
