/* eslint-disable camelcase */

import { expect } from "chai";
import { ethers, network, waffle } from "hardhat";
import {
  ERC20FLiqFEcoFBurnAntiDumpDexTempBan,
  ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory,
} from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, utils } from "ethers";
import {
  bigNumberToFloat,
  expandTo18Decimals,
  expandTo9Decimals,
} from "./shared/utilities";
import { abi } from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import { abi as busdABI } from "@uniswap/v2-periphery/build/ERC20.json";

// ATTENTION! do not commit the line below!! You should put only for your tests only!
//describe.only("ERC20FLiqFEcoFBurnAntiDumpDexTempBan", function () {
describe("ERC20FLiqFEcoFBurnAntiDumpDexTempBan", function () {
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
  let contract: ERC20FLiqFEcoFBurnAntiDumpDexTempBan;
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
    const ERC20Factory = <ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory>(
      await ethers.getContractFactory("ERC20FLiqFEcoFBurnAntiDumpDexTempBan")
    );
    contract = await ERC20Factory.deploy(
      "Test",
      "ERT",
      expandTo18Decimals(1000000000)
    );
    contract = await contract.deployed();
  });

  it("Should be constructed properly", async function () {
    expect(await contract.name()).to.equal("Test");
    expect(await contract.symbol()).to.equal("ERT");
    expect(await contract.totalSupply()).to.equal(
      utils.parseUnits("1000000000", 0).toString()
    );
    expect(await contract.decimals()).to.equal(18);
    expect(await contract.balanceOf(owner.address)).to.equal(
      await contract.totalSupply()
    );

    expect(
      await contract.isExcludedFromFees(await contract.DEAD_ADDRESS())
    ).to.equal(true);

    expect(await contract.isExcludedFromFees(await contract.owner())).to.equal(
      true
    );
  });

  it("Should be able to create a new pair", async function () {
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
    ).to.equal(expandTo9Decimals("1"));

    await contract.setBurnFee(0);
    await contract.setEcosystemFee(0);
    // await contract.setMaxTransferFee(3);
    await contract.setLiquidityFee(0);

    await contract
      .connect(address1)
      .transfer(address2.address, expandTo9Decimals("0.9"));

    // expect the burn address have the tokens
    expect(await contract.balanceOf(address2.address)).to.equal(
      expandTo9Decimals("0.9")
    );
  });

  describe("after liquidity is added", function () {
    const ROUTER_ADDRESS = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
    //   let BUSD_ADDRESS = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
    let router: Contract;
    //   let busd: Contract;
    //   let whale: SignerWithAddress;

    before(async function () {
      router = new ethers.Contract(ROUTER_ADDRESS, abi, owner);
      // busd = new ethers.Contract(BUSD_ADDRESS, busdABI, owner);

      // await network.provider.request({
      //   method: "hardhat_impersonateAccount",
      //   params: ["0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa"],
      // });

      // whale = await ethers.getSigner(
      //   "0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa"
      // );
    });

    beforeEach(async function () {
      await contract.setBurnFee(0);
      await contract.setEcosystemFee(0);
      await contract.setLiquidityFee(0);

      const tokenAmount = expandTo18Decimals(100000);

      const bnbAmount = expandTo18Decimals(1000);

      await contract.approve(router.address, ethers.constants.MaxUint256);

      // add liquidity to BNB liquidity pool
      await router.addLiquidityETH(
        contract.address,
        tokenAmount,
        0,
        0,
        owner.address,
        ethers.constants.MaxUint256,
        { value: bnbAmount }
      );

      // const busdAmount = expandTo18Decimals(100000);

      // await contract.connect(owner).transfer(whale.address, tokenAmount);

      // await contract
      //   .connect(whale)
      //   .approve(ROUTER_ADDRESS, ethers.constants.MaxUint256);

      // await busd
      //   .connect(whale)
      //   .approve(ROUTER_ADDRESS, ethers.constants.MaxUint256);

      // // add liquidity to BUSD liquidity pool
      // await router
      //   .connect(whale)
      //   .addLiquidity(
      //     contract.address,
      //     BUSD_ADDRESS,
      //     tokenAmount,
      //     busdAmount,
      //     0,
      //     0,
      //     whale.address,
      //     ethers.constants.MaxUint256
      //   );

      await contract.transfer(address1.address, expandTo18Decimals(10000));
    });

    it("should charge liquidity fee into liquidity pool", async function () {
      await contract.setLiquidityFee(ethers.utils.parseEther("0.1"));

      const initialReserves = bigNumberToFloat(
        await contract.balanceOf(await contract.dexPair())
      );

      await contract
        .connect(address1)
        .transfer(address2.address, expandTo18Decimals(500));

      expect(await contract.balanceOf(address2.address)).to.equal(
        expandTo18Decimals(450)
      );

      const finalReserves = bigNumberToFloat(
        await contract.balanceOf(await contract.dexPair())
      );

      expect(finalReserves).to.be.within(
        initialReserves + 49.9,
        initialReserves + 50
      );
    });

    describe("anti dump", function () {
      beforeEach(async function () {
        await contract.setAntiDump(
          ethers.utils.parseEther("0.01"),
          ethers.utils.parseEther("0.2")
        );

        await contract.setEcosystemFee(ethers.utils.parseEther("0.1"));
        await contract.setEcoSystemAddress(address3.address);
      });

      it("should activate anti dump mechanism if threshold is reached", async function () {
        await contract
          .connect(address1)
          .approve(router.address, expandTo18Decimals(1001));

        await router
          .connect(address1)
          .swapExactTokensForETHSupportingFeeOnTransferTokens(
            expandTo18Decimals(1001),
            0,
            [contract.address, router.WETH()],
            address1.address,
            ethers.constants.MaxUint256
          );

        // 30% (10% from ecoSystemFee + 20% from antiDumpFee)
        expect(await contract.balanceOf(address3.address)).to.equal(
          ethers.utils.parseEther("300.3")
        );
      });
    });
  });

  it("Automated Market Maker Pair", async function () {
    expect(await contract.setAutomatedMarketMakerPair(DEAD_ADDRESS, true));
  });

  // procurar como adicionar BUSD para cá
  /*
    it("Should be able to create a new pair", async function () {
        await contract._swapTokensForBNB(100);
    });
    */
});
