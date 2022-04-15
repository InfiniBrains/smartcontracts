/* eslint-disable camelcase */

import { expect } from "chai";
import { ethers } from "hardhat";
import {
  IUniswapV2Factory,
  IUniswapV2Pair,
  IUniswapV2Router02,
  UltimateERC20,
  UltimateERC20__factory,
} from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { utils } from "ethers";
import { expandTo9Decimals } from "./shared/utilities";
import { abi } from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import { abi as factoryAbi } from "@uniswap/v2-periphery/build/IUniswapV2Factory.json";
import { abi as pairAbi } from "@uniswap/v2-periphery/build/IUniswapV2Pair.json";

describe("UltimateCoin", function () {
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
  let contract: UltimateERC20;
  let owner: SignerWithAddress;
  let address1: SignerWithAddress;
  let address2: SignerWithAddress;
  let address3: SignerWithAddress;
  let address4: SignerWithAddress;

  before(async function () {
    [owner, address1, address2, address3, address4] = await ethers.getSigners();
  });

  beforeEach(async function () {
    const ultimateFactory = <UltimateERC20__factory>(
      await ethers.getContractFactory("UltimateERC20")
    );
    contract = await ultimateFactory.deploy("Test", "TST");
    contract = await contract.deployed();
  });

  it("Should be constructed properly", async function () {
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

    expect(await contract.isExcludedFromFee(await contract.owner())).to.equal(
      true
    );

    // await expect(
    //   await contract.setAutomatedMarketMakerPair(
    //     await contract.defaultPair(),
    //     true
    //   )
    // ).to.be.revertedWith("cannot be removed"); // should fail
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
    ).to.equal(expandTo9Decimals("0.99"));

    await contract.setBurnFeePercent(0, 0);
    await contract.setEcoSystemFeePercent(0, 0);
    await contract.setStakingFeePercent(0, 0);
    await contract.setLiquidityFeePercent(0, 0);
    await contract.setTaxFeePercent(0, 0);

    await contract
      .connect(address1)
      .transfer(address2.address, expandTo9Decimals("0.9"));

    // expect the burn address have the tokens
    expect(await contract.balanceOf(address2.address)).to.equal(
      expandTo9Decimals("0.9")
    );
  });

  it("Owner should not be able to set a new limit to add to liquidity lower than 0.000001% of total supply", async function () {
    await expect(
      contract.setNumTokensSellToAddToLiquidity(expandTo9Decimals("999"))
    ).to.be.revertedWith("new limit is too low");

    expect(await contract.numTokensSellToAddToLiquidity()).to.equal(
      expandTo9Decimals("1000")
    );
  });

  it("Owner should be able to set new limit to add to liquidity", async function () {
    await contract.setNumTokensSellToAddToLiquidity(expandTo9Decimals("100000"));

    expect(await contract.numTokensSellToAddToLiquidity()).to.equal(
      expandTo9Decimals("100000")
    );
  });

  describe("Fees", function () {
    beforeEach(async function () {
      await contract.setEcoSystemFeePercent(0, 0);
      await contract.setStakingFeePercent(0, 0);
      await contract.setLiquidityFeePercent(0, 0);
      await contract.setTaxFeePercent(0, 0);
      await contract.setBurnFeePercent(0, 0);

      await contract
        .connect(owner)
        .transfer(address1.address, expandTo9Decimals("1"));
    });

    it("Should calculate total fee correctly", async function () {
      expect(await contract.totalFees()).to.equal(expandTo9Decimals("0"));
      await contract.setTaxFeePercent(0, utils.parseEther("0.1"));
      await contract
        .connect(address1)
        .transfer(address2.address, expandTo9Decimals("1"));

      expect(await contract.totalFees()).to.equal(expandTo9Decimals("0.1"));
    });

    it("Should be able to transfer with BURN fee", async function () {
      await contract.setBurnFeePercent(0, utils.parseEther("0.1"));

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
      await contract.setEcoSystemFeePercent(0, utils.parseEther("0.1"));

      await contract.setEcoSystemFeeAddress(address3.address, address4.address);

      await contract
        .connect(address1)
        .transfer(address2.address, expandTo9Decimals("0.9"));

      expect(await contract.balanceOf(address4.address)).to.equal(
        expandTo9Decimals("0.09")
      );
    });

    it("Should charge staking fee", async function () {
      await contract.setStakingFeePercent(0, utils.parseEther("0.1"));

      await contract.setStakingFeeAddress(address3.address, address4.address);

      await contract
        .connect(address1)
        .transfer(address2.address, expandTo9Decimals("0.9"));

      expect(await contract.balanceOf(address4.address)).to.equal(
        expandTo9Decimals("0.09")
      );
    });

    describe("after liquidity is added", function () {
      const ROUTER_ADDRESS = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
      let router: IUniswapV2Router02;
      let WETH: string;
      let factory: IUniswapV2Factory;
      let pairContract: IUniswapV2Pair;

      before(async function () {
        router = <IUniswapV2Router02>(
          new ethers.Contract(ROUTER_ADDRESS, abi, owner)
        );
        WETH = await router.WETH();
        const factoryAddress = await router.factory();
        factory = <IUniswapV2Factory>(
          new ethers.Contract(factoryAddress, factoryAbi, owner)
        );
      });

      beforeEach(async function () {
        const pairAddress = await factory.getPair(contract.address, WETH);
        // PAIR CONTRACT
        pairContract = <IUniswapV2Pair>(
          new ethers.Contract(pairAddress, pairAbi, owner)
        );

        const TokenAmount = expandTo9Decimals("100000");

        const BNBAmount = expandTo9Decimals("1000");

        await contract.approve(ROUTER_ADDRESS, ethers.constants.MaxUint256);

        // add liquidity to liquidity pool
        await router
          .connect(owner)
          .addLiquidityETH(
            contract.address,
            TokenAmount,
            0,
            0,
            owner.address,
            ethers.constants.MaxUint256,
            { value: BNBAmount }
          );

        await contract.transfer(address1.address, expandTo9Decimals("10000"));
      });

      it("Should swap ETH for Tokens supporting fees on transfer", async function () {
        await contract.setEcoSystemFeePercent(0, utils.parseEther("0.01"));
        await contract.setStakingFeePercent(0, utils.parseEther("0.01"));
        await contract.setLiquidityFeePercent(0, utils.parseEther("0.01"));
        await contract.setTaxFeePercent(0, utils.parseEther("0.01"));
        await contract.setBurnFeePercent(0, utils.parseEther("0.01"));

        await expect(
          router
            .connect(address1)
            .swapExactETHForTokensSupportingFeeOnTransferTokens(
              0,
              [WETH, contract.address],
              address1.address,
              ethers.constants.MaxUint256,
              { value: utils.parseEther("10") }
            )
        ).to.emit(contract, "Transfer");
      });

      it("Should swap Tokens for ETH supporting fees on transfer", async function () {
        await contract.setEcoSystemFeePercent(0, utils.parseEther("0.01"));
        await contract.setStakingFeePercent(0, utils.parseEther("0.01"));
        await contract.setLiquidityFeePercent(0, utils.parseEther("0.01"));
        await contract.setTaxFeePercent(0, utils.parseEther("0.01"));
        await contract.setBurnFeePercent(0, utils.parseEther("0.01"));

        await contract
          .connect(address1)
          .approve(router.address, ethers.constants.MaxUint256);

        await expect(
          router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              expandTo9Decimals("1000"),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            )
        ).to.emit(contract, "Transfer");
      });

      describe("liquidity fee", function () {
        beforeEach(async function () {
          await contract.setLiquidityFeePercent(0, utils.parseEther("0.1"));
        });

        it("Should add liquidity to LP and cashback to user", async function () {
          await contract.enableSwapAndLiquify();

          const initialCakeBalance = await pairContract.balanceOf(
            address1.address
          );

          await contract
            .connect(address1)
            .transfer(address2.address, expandTo9Decimals("10000"));

          const finalCakeBalance = await pairContract.balanceOf(
            address1.address
          );

          expect(await contract.balanceOf(contract.address)).to.equal(0);
          expect(
            await contract.balanceOf(await contract.defaultPair())
          ).to.equal(expandTo9Decimals("101000"));
          expect(initialCakeBalance).to.be.lt(finalCakeBalance);
        });

        it("Should add liquidity to LP and cashback to liquidity address", async function () {
          await contract.setLiqudityFeeAddress(address3.address);
          await contract.enableSwapAndLiquify();
          expect(await contract.balanceOf(contract.address)).to.equal(0);

          const initialCakeBalance = await pairContract.balanceOf(
            address3.address
          );

          await contract
            .connect(address1)
            .transfer(address2.address, expandTo9Decimals("10000"));

          const finalCakeBalance = await pairContract.balanceOf(
            address3.address
          );

          expect(await contract.balanceOf(contract.address)).to.equal(0);
          expect(
            await contract.balanceOf(await contract.defaultPair())
          ).to.equal(expandTo9Decimals("101000"));
          expect(initialCakeBalance).to.be.lt(finalCakeBalance);
        });

        it("Should not add liquidity to LP if contract balance is less than minimum amount to add to liquidity", async function () {
          await contract.enableSwapAndLiquify();
          await contract
            .connect(address1)
            .transfer(address2.address, expandTo9Decimals("200"));

          await contract
            .connect(address2)
            .transfer(address3.address, expandTo9Decimals("100"));

          expect(await contract.balanceOf(contract.address)).to.equal(
            expandTo9Decimals("30")
          );

          expect(
            await contract.balanceOf(await contract.defaultPair())
          ).to.equal(expandTo9Decimals("100000")); // liquidity is the same as initial
        });

        it("Should not add liquidity to LP if swapAndLiquify is not enabled", async function () {
          await contract
            .connect(address1)
            .transfer(address2.address, expandTo9Decimals("10000"));

          const finalCakeBalance = await pairContract.balanceOf(
            address1.address
          );

          expect(await contract.balanceOf(contract.address)).to.equal(
            expandTo9Decimals("1000")
          );
          expect(
            await contract.balanceOf(await contract.defaultPair())
          ).to.equal(expandTo9Decimals("100000")); // liquidity is the same as initial
          expect(finalCakeBalance).to.be.equal(0);
        });
      });

      describe("Anti dump", function () {
        beforeEach(async function () {
          await contract.setTaxFeePercent(0, utils.parseEther("0.05")); // 5% tax fee

          await contract.excludeFromReward(owner.address); // exclude owner from reward
        });

        it("should activate anti dump mechanism if threshold is reached", async function () {
          await contract
            .connect(address1)
            .approve(router.address, expandTo9Decimals("500"));

          await router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              expandTo9Decimals("500"),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            );

          // 30% (5% from taxFee + 25% from antiDumpFee)
          expect(await contract.balanceOf(address1.address)).to.equal(
            expandTo9Decimals("9513.973482262")
          );

          expect(await contract.balanceOf(pairContract.address)).to.equal(
            expandTo9Decimals("100487.026517737")
          );
        });
      });

      describe("timelock dex", async function () {
        const oneDay = 24 * 60 * 60;

        beforeEach(async function () {
          await contract.setLockTime(oneDay);

          await contract
            .connect(address1)
            .approve(router.address, expandTo9Decimals("1000"));
        });

        it("should revert if user tries to transact to dex before timelock expires", async function () {
          await router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              expandTo9Decimals("500"),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            );

          await expect(
            router
              .connect(address1)
              .swapExactTokensForETHSupportingFeeOnTransferTokens(
                expandTo9Decimals("500"),
                0,
                [contract.address, WETH],
                address1.address,
                ethers.constants.MaxUint256
              )
          ).to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED");
        });

        it("should pass if user tries to transact to dex after timelock expires", async function () {
          await router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              expandTo9Decimals("500"),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            );

          // jump one day in time
          await ethers.provider.send("evm_increaseTime", [oneDay]);
          await ethers.provider.send("evm_mine", []);

          await expect(
            router
              .connect(address1)
              .swapExactTokensForETHSupportingFeeOnTransferTokens(
                expandTo9Decimals("500"),
                0,
                [contract.address, WETH],
                address1.address,
                ethers.constants.MaxUint256
              )
          ).to.emit(contract, "Transfer");
        });
      });
    });

    describe("Reflect fee", async function () {
      beforeEach(async function () {
        await contract.setTaxFeePercent(0, utils.parseEther("0.01"));

        await contract.excludeFromReward(owner.address); // exclude owner from reward
        await contract.transfer(address1.address, expandTo9Decimals("10000"));
      });

      // it("Check gas price",async function(){
      //   await contract.connect(owner).setTaxFeePercent(100,100);
      //   await contract.connect(owner).setEcoSystemFeePercent(100, 100);
      //   await contract.connect(owner).setBurnFeePercent(100, 100);
      //   await contract.connect(owner).setLiquidityFeePercent(100,100);
      //
      //   console.log("ultimate");
      //   console.log(await contract
      //       .connect(address1).estimateGas
      //       .transfer(address2.address, expandTo9Decimals("500")));
      // });

      it("Should charge reflect fee", async function () {
        expect(await contract.balanceOf(owner.address)).to.equal(
          expandTo9Decimals("999989999")
        ); // should not charge on owner transfer

        expect(await contract.balanceOf(address1.address)).to.equal(
          expandTo9Decimals("10001")
        ); // should not charge on owner transfer

        await contract
          .connect(address1)
          .transfer(address2.address, expandTo9Decimals("10000"));

        expect(await contract.balanceOf(owner.address)).to.equal(
          expandTo9Decimals("999989999")
        );

        expect(await contract.balanceOf(address1.address)).to.equal(
          expandTo9Decimals("1.010099989")
        );

        expect(await contract.balanceOf(address2.address)).to.equal(
          expandTo9Decimals("9999.98990001")
        );
      });
    });
  });

  it("Automated Market Maker Pair", async function () {
    expect(await contract.setAutomatedMarketMakerPair(DEAD_ADDRESS, true));
  });

  // todo: implement deployment of dexes
  // it("Timelock DEX transfer", async function () {
  //   await contract.setBurnFeePercent(0, 0);
  //   await contract.setEcoSystemFeePercent(0, 0);
  //   await contract.setLiquidityFeePercent(0, 0);
  //   await contract.setTaxFeePercent(0, 0);
  // });
});
