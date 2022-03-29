// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
//import {TolstaCoin, TolstaCoin__factory} from "../typechain";
import { ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory } from "../typechain";

import {Wallet} from "ethers";
import {Provider} from "@ethersproject/providers";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  /*let tolstaCoinFactory = <TolstaCoin__factory>await ethers.getContractFactory("TolstaCoin");
  const greeter = await tolstaCoinFactory.deploy();
  let tx = await greeter.deployed();

  console.log("Tolstacoin deployed to: " + tx.address)*/
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const tokenFactory: ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory = await ethers.getContractFactory("ERC20FLiqFEcoFBurnAntiDumpDexTempBan");
  let token: Contract = await tokenFactory.deploy();
  token = await token.deployed();

  console.log("token deployed to: ", token.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
