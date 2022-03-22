/* eslint-disable camelcase */
import { expect } from "chai";
import { ethers } from "hardhat";
import { UltimateERC20, UltimateERC20__factory } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { utils } from "ethers";
import { expandTo9Decimals } from "./shared/utilities";

describe.only("UltimateCoin", function () {
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
  let contract: UltimateERC20;
  let owner: SignerWithAddress;
  let address1: SignerWithAddress;
  let address2: SignerWithAddress;
  let address3: SignerWithAddress;
  let address4: SignerWithAddress;
  let address5: SignerWithAddress;

  before(async function () {
    [owner, address1, address2, address3, address4, address5] =
      await ethers.getSigners();
  });

  beforeEach(async function () {
    const ultimateFactory = <UltimateERC20__factory>(
      await ethers.getContractFactory("UltimateERC20")
    );
    contract = await ultimateFactory.deploy("Test", "TST");
    contract = await contract.deployed();
  });

  it("Should be contructed properly", async function () {
    expect(await contract.name()).to.equal("Test");
    expect(await contract.symbol()).to.equal("TST");
    expect(await contract.totalSupply()).to.equal(
      utils.parseUnits("1000000000", 9).toString()
    );
    expect(await contract.decimals()).to.equal(9);
    expect(await contract.balanceOf(owner.address)).to.equal(
      await contract.totalSupply()
    );
    expect(
      await contract.isExcludedFromReward(await contract._burnAddress())
    ).to.equal(true);
  });

  it("should be able to create a new pair", async function () {
    const tx = await contract.addNewPair(
      "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
    ); // BUSD address
    const receipt = await tx.wait();
    const newPair: string = utils.defaultAbiCoder.decode(
      ["address"],
      receipt.logs[2].topics[2]
    )[0];

    expect(await contract.automatedMarketMakerPairs(newPair)).to.equal(true);
    await expect(
      contract.addNewPair("0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56")
    ).to.be.revertedWith("Pancake: PAIR_EXISTS"); // should fail
  });

  it("Should be able to transfer without fees", async function () {
    // owner transfer: should charge small fees
    await contract
      .connect(owner)
      .transfer(address1.address, expandTo9Decimals("1"));
    expect(
      await contract.connect(address1).balanceOf(address1.address)
    ).to.equal(expandTo9Decimals("0.99"));

    await contract.setBurnFeePercent(0, 0);
    await contract.setEcoSystemFeePercent(0, 0);
    await contract.setRewardFeePercent(0, 0);
    await contract.setLiquidityFeePercent(0, 0);
    await contract.setTaxFeePercent(0, 0);

    await contract
      .connect(address1)
      .transfer(address2.address, expandTo9Decimals("0.9"));

    expect(await contract.balanceOf(address2.address)).to.equal(
      expandTo9Decimals("0.9")
    );
  });

  describe("Fees", function () {
    beforeEach(async function () {
      await contract
        .connect(owner)
        .transfer(address1.address, expandTo9Decimals("1"));
    });

    it("Should be able to transfer with BURN fee", async function () {
      await contract.setEcoSystemFeePercent(0, 0);
      await contract.setRewardFeePercent(0, 0);
      await contract.setLiquidityFeePercent(0, 0);
      await contract.setTaxFeePercent(0, 0);
      await contract.setBurnFeePercent(0, 1000);

      // expect the value be lower than the transferred
      await contract
        .connect(address1)
        .transfer(address2.address, expandTo9Decimals("0.9"));
      expect(
        await contract.connect(address2).balanceOf(address2.address)
      ).to.equal(expandTo9Decimals("0.81"));

      // expect the burn address have the tokens
      expect(
        await contract
          .connect(address2)
          .balanceOf(await contract._burnAddress())
      ).to.equal(expandTo9Decimals("0.09"));
    });

    it("Should charge ecosystem fee", async function () {
      await contract.setRewardFeePercent(0, 0);
      await contract.setLiquidityFeePercent(0, 0);
      await contract.setTaxFeePercent(0, 0);
      await contract.setBurnFeePercent(0, 0);
      await contract.setEcoSystemFeePercent(0, 1000);

      await contract.setEcoSystemFeeAddress(address3.address, address4.address);

      await contract
        .connect(address1)
        .transfer(address2.address, expandTo9Decimals("0.9"));

      expect(await contract.balanceOf(address4.address)).to.equal(
        expandTo9Decimals("0.09")
      );
    });

    it("Should charge reward fee", async function () {
      await contract.setEcoSystemFeePercent(0, 0);
      await contract.setLiquidityFeePercent(0, 0);
      await contract.setTaxFeePercent(0, 0);
      await contract.setBurnFeePercent(0, 0);
      await contract.setRewardFeePercent(0, 1000);

      await contract.setRewardFeeAddress(address3.address, address4.address);

      await contract
        .connect(address1)
        .transfer(address2.address, expandTo9Decimals("0.9"));

      expect(await contract.balanceOf(address4.address)).to.equal(
        expandTo9Decimals("0.09")
      );
    });
  });

  // todo: implement deployment of dexes
  // it("Timelock DEX transfer", async function () {
  //   await contract.setBurnFeePercent(0, 0);
  //   await contract.setEcoSystemFeePercent(0, 0);
  //   await contract.setLiquidityFeePercent(0, 0);
  //   await contract.setTaxFeePercent(0, 0);
  // });
});
