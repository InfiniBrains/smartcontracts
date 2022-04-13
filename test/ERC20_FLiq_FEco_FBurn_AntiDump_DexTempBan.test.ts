/* eslint-disable camelcase */

import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  ERC20FLiqFEcoFBurnAntiDumpDexTempBan,
  ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory,
  IUniswapV2Router02,
} from "../typechain";
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
import busdAbi from "./shared/busd.json";

// ATTENTION! do not commit the line below!! You should put only for your tests only!
// describe.only("ERC20FLiqFEcoFBurnAntiDumpDexTempBan", function () {
describe("ERC20FLiqFEcoFBurnAntiDumpDexTempBan", function () {
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
  const BUSD_ADDRESS = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
  const ROUTER_ADDRESS = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
  let WETH: string;
  let contract: ERC20FLiqFEcoFBurnAntiDumpDexTempBan;
  let router: IUniswapV2Router02;
  let factory: Contract;
  let busdContract: Contract;
  const busdHotWalletAddress: string =
    "0x8894e0a0c962cb723c1976a4421c95949be2d4e3";
  let busdHotWallet: SignerWithAddress;
  let pairContract: Contract;
  let owner: SignerWithAddress;
  let address1: SignerWithAddress;
  let address2: SignerWithAddress;
  let address3: SignerWithAddress;
  let address4: SignerWithAddress;
  let tokenGiver: SignerWithAddress;

  before(async function () {
    [owner, address1, address2, address3, address4, tokenGiver] =
      await ethers.getSigners();

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [busdHotWalletAddress],
    });

    // BUSD contract
    busdHotWallet = await ethers.getSigner(busdHotWalletAddress);
    busdContract = new ethers.Contract(BUSD_ADDRESS, busdAbi, busdHotWallet);

    let bal = await ethers.provider.getBalance(owner.address);

    // ROUTER CONTRACT
    router = <IUniswapV2Router02>(
      new ethers.Contract(ROUTER_ADDRESS, abi, owner)
    );
    WETH = await router.WETH();

    // FACTORY CONTRACT
    const factoryAddress = await router.factory();
    factory = new ethers.Contract(factoryAddress, factoryAbi, owner);

    // BNB FUNDING
    await busdHotWallet.sendTransaction({
      to: owner.address,
      value: expandTo18Decimals(100),
    });
    bal = await ethers.provider.getBalance(owner.address);
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
    const pairAddress = await factory.getPair(contract.address, WETH);
    // PAIR CONTRACT
    pairContract = new ethers.Contract(pairAddress, pairAbi, owner);
  });

  it("Should be constructed properly", async function () {
    expect(await contract.name()).to.equal("Test");
    expect(await contract.symbol()).to.equal("ERT");
    expect(await contract.totalSupply()).to.equal(
      expandTo18Decimals(1000000000)
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
    beforeEach(async function () {
      tokenGiver.sendTransaction({
        to: owner.address,
        value: expandTo18Decimals(500),
      });

      await contract.setBurnFee(0);
      await contract.setEcosystemFee(0);
      await contract.setLiquidityFee(0);

      const tokenAmount = expandTo18Decimals(10000000);

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

      await contract.transfer(address1.address, expandTo18Decimals(100000));
    });

    it("Should swap ETH for Tokens supporting fees on transfer", async function () {
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
      await contract
        .connect(address1)
        .approve(router.address, ethers.constants.MaxUint256);

      await expect(
        router
          .connect(address1)
          .swapExactTokensForETHSupportingFeeOnTransferTokens(
            utils.parseEther("1000"),
            0,
            [contract.address, WETH],
            address1.address,
            ethers.constants.MaxUint256
          )
      ).to.emit(contract, "Transfer");
    });

    it("liquidityAddress should receive cakes on sell", async function () {
      await contract
        .connect(owner)
        .setEcosystemFee(ethers.utils.parseEther("0"));
      await contract.connect(owner).setBurnFee(ethers.utils.parseEther("0"));
      await contract
        .connect(owner)
        .setLiquidityFee(ethers.utils.parseEther("0.01"));
      await contract.connect(owner).setLiquidityAddress(owner.address);

      await contract
        .connect(address1)
        .approve(router.address, expandTo18Decimals(100000));

      const initialPairBalance = bigNumberToFloat(
        await pairContract.balanceOf(await contract.liquidityAddress())
      );
      const initialReserves = bigNumberToFloat(
        await contract.balanceOf(await contract.dexPair())
      );

      await router
        .connect(address1)
        .swapExactTokensForETHSupportingFeeOnTransferTokens(
          expandTo18Decimals(100000),
          0,
          [contract.address, WETH],
          address1.address,
          ethers.constants.MaxUint256
        );

      const finalReserves = bigNumberToFloat(
        await contract.balanceOf(await contract.dexPair())
      );
      const finalPairBalance = bigNumberToFloat(
        await pairContract.balanceOf(await contract.liquidityAddress())
      );

      expect(initialPairBalance).lt(finalPairBalance);
      expect(initialReserves).lt(finalReserves);
    });

    it("user should receive cakes as cashback on sell", async function () {
      await contract
        .connect(owner)
        .setLiquidityFee(ethers.utils.parseEther("0.1"));
      await contract
        .connect(owner)
        .setEcosystemFee(ethers.utils.parseEther("0"));
      await contract.connect(owner).setBurnFee(ethers.utils.parseEther("0"));

      await contract
        .connect(address1)
        .approve(router.address, expandTo18Decimals(1));

      const initialCakeBalance = bigNumberToFloat(
        await pairContract.balanceOf(address1.address)
      );

      await router
        .connect(address1)
        .swapExactTokensForETHSupportingFeeOnTransferTokens(
          expandTo18Decimals(1),
          0,
          [contract.address, WETH],
          address1.address,
          ethers.constants.MaxUint256
        );

      const finalCakeBalance = bigNumberToFloat(
        await pairContract.balanceOf(address1.address)
      );

      expect(initialCakeBalance).lt(finalCakeBalance);
    });

    describe("liquidity fee", function () {
      describe("test liquidity fee limits", async function () {
        await expect(
          contract.setNumTokensSellToAddToLiquidity(
            ethers.utils.parseEther("0")
          )
        ).to.be.revertedWith("new limit is too low");

        await expect(
          contract.setNumTokensSellToAddToLiquidity(
            ethers.utils.parseEther("100")
          )
        ).to.be.revertedWith("new limit is too low");
      });

      describe("buy from dex", function () {
        it("Should send liquidity fee to token contract", async function () {
          await contract.setLiquidityFee(ethers.utils.parseEther("0.01"));

          const amountsOut = await router.getAmountsOut(
            utils.parseEther("10"),
            [WETH, contract.address]
          );

          await router
            .connect(address1)
            .swapExactETHForTokensSupportingFeeOnTransferTokens(
              0,
              [WETH, contract.address],
              address4.address,
              ethers.constants.MaxUint256,
              { value: utils.parseEther("10") }
            );

          expect(await contract.balanceOf(address4.address)).to.equal(
            amountsOut[amountsOut.length - 1].sub(
              amountsOut[amountsOut.length - 1].div(100)
            )
          );

          expect(await contract.balanceOf(contract.address)).to.equal(
            amountsOut[amountsOut.length - 1].div(100)
          );
        });
      });

      describe("selling to dex", function () {
        it("Should not swapAndLiqufy if amount to liquidity is less then numTokensSellToAddToLiquidity and lpAddress is set", async function () {
          await contract.setLiquidityFee(ethers.utils.parseEther("0.01"));
          await contract.setLiquidityAddress(address4.address);

          const initialCakeBalance = await pairContract.balanceOf(
            await contract.liquidityAddress()
          );

          await contract
            .connect(address1)
            .approve(
              router.address,
              (await contract.numTokensSellToAddToLiquidity()).mul(10)
            );

          await router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              (await contract.numTokensSellToAddToLiquidity()).mul(10),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            );

          const finalCakeBalance = await pairContract.balanceOf(
            await contract.liquidityAddress()
          );

          expect(await contract.balanceOf(contract.address)).to.be.equal(
            (await contract.numTokensSellToAddToLiquidity()).div(10)
          );
          expect(initialCakeBalance).to.be.equal(finalCakeBalance);
        });

        it("Should swapAndLiquify all contract balance to dex if lpAddress is set", async function () {
          await contract.setLiquidityFee(ethers.utils.parseEther("0.01"));
          await contract.setLiquidityAddress(address4.address);

          const initialCakeBalance = await pairContract.balanceOf(
            await contract.liquidityAddress()
          );

          await contract
            .connect(address1)
            .approve(
              router.address,
              (await contract.numTokensSellToAddToLiquidity()).mul(100)
            );

          await router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              (await contract.numTokensSellToAddToLiquidity()).mul(100),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            );

          const finalCakeBalance = await pairContract.balanceOf(
            await contract.liquidityAddress()
          );

          expect(await contract.balanceOf(contract.address)).to.be.lt(
            await contract.numTokensSellToAddToLiquidity()
          );
          expect(initialCakeBalance).to.be.lt(finalCakeBalance);
        });

        it("Should swapAndLiquify tokens to liquidit if lpAddress is not set", async function () {
          await contract.setLiquidityFee(ethers.utils.parseEther("0.01"));

          const initialCakeBalance = await pairContract.balanceOf(
            address1.address
          );

          await contract
            .connect(address1)
            .approve(router.address, utils.parseEther("1000"));

          await router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              utils.parseEther("1000"),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            );

          const finalCakeBalance = await pairContract.balanceOf(
            address1.address
          );

          expect(await contract.balanceOf(contract.address)).to.be.lt(
            utils.parseEther("1000").div(100)
          );
          expect(initialCakeBalance).to.be.lt(finalCakeBalance);
        });
      });
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
        await contract.transfer(address1.address, expandTo18Decimals(1));

        await contract
          .connect(address1)
          .approve(router.address, expandTo18Decimals(100001));

        await router
          .connect(address1)
          .swapExactTokensForETHSupportingFeeOnTransferTokens(
            expandTo18Decimals(100001),
            0,
            [contract.address, WETH],
            address1.address,
            ethers.constants.MaxUint256
          );

        // 30% (10% from ecoSystemFee + 20% from antiDumpFee)
        expect(await contract.balanceOf(address3.address)).to.equal(
          ethers.utils.parseEther("30000.3")
        );
      });

      // it("Check gas price", async function () {
      //   await contract
      //     .connect(owner)
      //     .setEcosystemFee(ethers.utils.parseEther("0.01"));
      //   await contract
      //     .connect(owner)
      //     .setBurnFee(ethers.utils.parseEther("0.01"));
      //   await contract
      //     .connect(owner)
      //     .setLiquidityFee(ethers.utils.parseEther("0.01"));
      //   await contract.connect(owner).setLiquidityAddress(owner.address);
      //
      //   console.log("erc20 with fees");
      //   console.log(
      //     await contract
      //       .connect(address1)
      //       .estimateGas.transfer(address2.address, expandTo9Decimals("500"))
      //   );
      // });
    });

    describe("timelock dex", async function () {
      const oneDay = 24 * 60 * 60;

      beforeEach(async function () {
        await contract.setLockTime(oneDay);

        await contract
          .connect(address1)
          .approve(router.address, expandTo18Decimals(1000));
      });

      it("should revert if user tries to transact to dex before timelock expires", async function () {
        await router
          .connect(address1)
          .swapExactTokensForETHSupportingFeeOnTransferTokens(
            expandTo18Decimals(500),
            0,
            [contract.address, WETH],
            address1.address,
            ethers.constants.MaxUint256
          );

        await expect(
          router
            .connect(address1)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
              expandTo18Decimals(500),
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
            expandTo18Decimals(500),
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
              expandTo18Decimals(500),
              0,
              [contract.address, WETH],
              address1.address,
              ethers.constants.MaxUint256
            )
        )
          .to.emit(contract, "Transfer")
          .withArgs(
            address1.address,
            await contract.dexPair(),
            expandTo18Decimals(500)
          );
      });
    });
  });

  it("Automated Market Maker Pair", async function () {
    expect(await contract.setAutomatedMarketMakerPair(DEAD_ADDRESS, true));
  });

  it("should start busd liquidity", async function () {
    await busdContract
      .connect(busdHotWallet)
      .transfer(owner.address, expandTo18Decimals(1000000));

    const balanceBusdOwner = await busdContract.balanceOf(owner.address);
    expect(balanceBusdOwner).to.equal(expandTo18Decimals(1000000));
  });

  it("should transfer liquidity tokens to designated liquidity address", async function () {
    // how to get liquidity token address?
  });

  // procurar como adicionar BUSD para cá
  /*
    it("Should be able to create a new pair", async function () {
        await contract._swapTokensForBNB(100);
    });
    */
});
