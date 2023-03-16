import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Blackjack, Blackjack__factory } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, utils } from "ethers";
import {
  bigNumberToFloat,
  expandTo9Decimals,
  expandTo18Decimals,
} from "./shared/utilities";
import { abi } from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import { abi as factoryAbi } from "@uniswap/v2-periphery/build/IUniswapV2Factory.json";
import { abi as pairAbi } from "@uniswap/v2-periphery/build/IUniswapV2Pair.json";

describe("BlackJack", function () {
  let contract: Blackjack;
  beforeEach(async function () {
    const BlackJackFactory = <Blackjack__factory>(
      await ethers.getContractFactory("Blackjack")
    );
    contract = await upgrades.deployProxy(BlackJackFactory);
    await contract.deployed();
  });

  it("Two calls of random should generate different values", async function () {
    const result1 = await contract.random();
    const result2 = await contract.random();
    expect(result1.value !== result2.value);
  });
});
