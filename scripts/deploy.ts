import { ethers } from "hardhat";

async function main() {
  const contractName = process.env.CONTRACT_NAME || "ColorGridGame";
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy();
  await contract.waitForDeployment();

  console.log(`${contractName} deployed to ${contract.target}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
