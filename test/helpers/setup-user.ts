import { ethers, deployments } from 'hardhat';

export const setupUsers = deployments.createFixture(async () => {
	const signers = await ethers.getSigners();

	return {
		admin: signers[0],
		alice: signers[1],
		bob: signers[2],
		eve: signers[3],
	}
})