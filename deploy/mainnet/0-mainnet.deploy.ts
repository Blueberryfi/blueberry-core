import fs from "fs";
import { ethers, upgrades, network } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { AggregatorOracle, BandAdapterOracle, BlueBerryBank, ChainlinkAdapterOracle, CoreOracle, IchiVaultOracle, IchiSpell, ProtocolConfig, UniswapV3AdapterOracle, WERC20, WIchiFarm } from '../../typechain-types';

const deploymentPath = "./deployments";
const deploymentFilePath = `${deploymentPath}/${network.name}.json`;

async function main(): Promise<void> {
	const [deployer] = await ethers.getSigners();

	const deployment = fs.existsSync(deploymentFilePath)
    ? JSON.parse(fs.readFileSync(deploymentFilePath).toString())
    : {};
	const coreOracle = <CoreOracle>await ethers.getContractAt(CONTRACT_NAMES.CoreOracle, deployment.CoreOracle);

	// Ichi Lp Oracle
	const IchiVaultOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultOracle);
	const ichiVaultOracle = <IchiVaultOracle>await IchiVaultOracle.deploy(coreOracle.address);
	await ichiVaultOracle.deployed();
	console.log('Ichi Lp Oracle Address:', ichiVaultOracle.address);

	await coreOracle.setRoutes(
		[ADDRESS.ICHI_VAULT_USDC],
		[ichiVaultOracle.address]
	);

	// Bank
	const Config = await ethers.getContractFactory("ProtocolConfig");
	const config = <ProtocolConfig>await upgrades.deployProxy(Config, [deployer]);
	await config.deployed();

	const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
	const bank = <BlueBerryBank>await upgrades.deployProxy(BlueBerryBank, [coreOracle.address, config.address, 2000]);
	await bank.deployed();

	// WERC20 of Ichi Vault Lp
	const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
	const werc20 = <WERC20>await WERC20.deploy();
	await werc20.deployed();

	// WIchiFarm
	const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
	const wichiFarm = <WIchiFarm>await upgrades.deployProxy(WIchiFarm, [ADDRESS.ICHI, ADDRESS.ICHI_FARMING]);
	await wichiFarm.deployed();

	// Ichi Vault Spell
	const IchiSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiSpell);
	const ichiSpell = <IchiSpell>await upgrades.deployProxy(IchiSpell, [
		bank.address,
		werc20.address,
		ADDRESS.WETH,
		wichiFarm.address,
		ADDRESS.UNI_V3_ROUTER
	]);
	await ichiSpell.deployed();
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
