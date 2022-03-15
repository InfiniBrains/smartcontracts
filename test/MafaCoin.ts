/* eslint-disable camelcase */
import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, utils } from "ethers";
import { MafaCoin, MafaCoin__factory } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import uniswaprouter from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import { bigNumberToFloat, expandTo18Decimals } from "./shared/utilities";

describe("MafaCoin", function () {
    const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
    let contract: MafaCoin;
    let owner: SignerWithAddress;
    let address1: SignerWithAddress;
    let address2: SignerWithAddress;
    let address3: SignerWithAddress;
    let address4: SignerWithAddress;
    let address5: SignerWithAddress;
    before(async function () {
        [owner, address1, address2, address3, address4, address5] = await ethers.getSigners();
    });
    beforeEach(async function () {
        const MafaCoinFactory: MafaCoin__factory = await ethers.getContractFactory("MafaCoin");
        contract = await MafaCoinFactory.deploy();
        contract = await contract.deployed();
        await contract.afterPreSale();
        await contract.setTeamWallet(address1.address);
        await contract.setLotteryWallet(address2.address);
    });
    it("should have the correct name and symbol", async function () {
        const name = await contract.name();
        const symbol = await contract.symbol();
        expect(name).to.equal("MafaCoin");
        expect(symbol).to.equal("MAFA");
    });

    it("should stop burn fee after 50% of the total supply is burned", async function () {
        const initialBurnFee = await contract.burnFee();

        await contract.transfer(DEAD_ADDRESS, utils.parseEther("500000000").toString());
        await contract.transfer(address3.address, 100);
        const totalSupply = await contract.totalSupply();

        const totalBurned = await contract.balanceOf(DEAD_ADDRESS);

        const burnFee = await contract.burnFee();

        expect(totalSupply).to.equal(utils.parseEther("1000000000").toString());
        expect(totalBurned).to.equal(utils.parseEther("500000000").toString());
        expect(initialBurnFee).to.equal(1);
        expect(burnFee).to.equal(0);
    });

    it("should maintain burn fee if 49% of the total supply is burned", async function () {
        const initialBurnFee = await contract.burnFee();

        await contract.transfer(DEAD_ADDRESS, utils.parseEther("490000000").toString());
        await contract.transfer(address3.address, 100);

        const burnFee = await contract.burnFee();

        expect(initialBurnFee).to.equal(1);
        expect(burnFee).to.equal(1);
    });

    it("should charge buy fees", async function () {
        await contract.setLiquidyFee(0);

        await contract.transfer(address3.address, utils.parseEther("1000").toString());
        await contract.connect(address3).transfer(address4.address, utils.parseEther("1000").toString());
        const zeroBalance = bigNumberToFloat(await contract.balanceOf(address3.address));
        const balanceTaxed = bigNumberToFloat(await contract.balanceOf(address4.address));
        const teamBalance = bigNumberToFloat(await contract.balanceOf(address1.address));
        const burnBalance = bigNumberToFloat(await contract.balanceOf(DEAD_ADDRESS));
        expect(zeroBalance).to.equal(0);
        expect(balanceTaxed).to.equal(980);
        expect(teamBalance).to.equal(10);
        expect(burnBalance).to.equal(10);
    });
    describe("DEX", function () {
        const ROUTER_ADDRESS = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
        let router: Contract;
        before(async function () {
            router = new ethers.Contract(ROUTER_ADDRESS, uniswaprouter.abi);
        });

        it("should have the correct liquidity fee", async function () {
            const liquidityFee = await contract.liquidityFee();

            expect(liquidityFee).to.equal(3);
        });

        it("should have the correct router address", async function () {
            await contract.startLiquidity(router.address);
            const dexRouter = await contract.dexRouter();
            expect(dexRouter).to.equal(ROUTER_ADDRESS);
        });
        it("should charge buy fees with liquidity fee", async function () {
            await contract.startLiquidity(router.address);
            const MAFAAmount = expandTo18Decimals(1000);
            const ETHAmount = expandTo18Decimals(10);
            await contract.approve(router.address, ethers.constants.MaxUint256);
            // add liquidity to liquidity pool
            await router
                .connect(owner)
                .addLiquidityETH(
                    contract.address,
                    MAFAAmount,
                    MAFAAmount,
                    ETHAmount,
                    owner.address,
                    ethers.constants.MaxUint256,
                    { value: ETHAmount },
                );
            // first transaction from owner, should not charge fees
            await contract.transfer(address3.address, MAFAAmount);
            // sencond transaction from address3, should charge fees
            const transactAmount = expandTo18Decimals(100);
            await contract.connect(address3).transfer(address4.address, transactAmount);
            // third transaction from address4, should charge fees
            const transactAmount2 = expandTo18Decimals(95);
            await contract.connect(address4).transfer(address5.address, transactAmount2);
            const pairBalance = bigNumberToFloat(await contract.balanceOf(await contract.dexPair()));
            const deadBalance = bigNumberToFloat(await contract.balanceOf(DEAD_ADDRESS));
            const teamBalance = bigNumberToFloat(await contract.balanceOf(address1.address));
            const lotteryBalance = bigNumberToFloat(await contract.balanceOf(address2.address));
            const address3Balance = bigNumberToFloat(await contract.balanceOf(address3.address));
            const address4Balance = bigNumberToFloat(await contract.balanceOf(address4.address));
            const address5Balance = bigNumberToFloat(await contract.balanceOf(address5.address));
            expect(pairBalance).to.be.within(1005.8, 1006);
            expect(deadBalance).to.equal(1.95);
            expect(teamBalance).to.equal(1.95);
            expect(lotteryBalance).to.equal(0);
            expect(address3Balance).to.equal(900);
            expect(address4Balance).to.equal(0);
            expect(address5Balance).to.equal(90.25);
        });
        it("should revert transaction if pool doesn't have enough liquidity", async function () {
            await contract.startLiquidity(router.address);
            const MAFAAmount = expandTo18Decimals(1000);
            await contract.transfer(address3.address, MAFAAmount);
            const transactAmount = expandTo18Decimals(100);
            await expect(contract.connect(address3).transfer(address4.address, transactAmount)).to.be.revertedWith(
                "PancakeLibrary: INSUFFICIENT_LIQUIDITY",
            );
        });
        it("should charge sell fees when transfering tokens to pair", async function () {
            await contract.startLiquidity(router.address);
            const MAFAAmount = expandTo18Decimals(1000);
            const ETHAmount = expandTo18Decimals(10);
            await contract.approve(router.address, ethers.constants.MaxUint256);
            await router
                .connect(owner)
                .addLiquidityETH(
                    contract.address,
                    MAFAAmount,
                    MAFAAmount,
                    ETHAmount,
                    owner.address,
                    ethers.constants.MaxUint256,
                    { value: ETHAmount },
                );
            await contract.transfer(address3.address, MAFAAmount);
            const dexPair = await contract.dexPair();
            const transactAmount = expandTo18Decimals(100);
            await contract.connect(address3).transfer(dexPair, transactAmount);
            const deadBalance = bigNumberToFloat(await contract.balanceOf(DEAD_ADDRESS));
            const teamBalance = bigNumberToFloat(await contract.balanceOf(address1.address));
            const lotteryBalance = bigNumberToFloat(await contract.balanceOf(address2.address));
            const address3Balance = bigNumberToFloat(await contract.balanceOf(address3.address));
            const pairBalance = bigNumberToFloat(await contract.balanceOf(dexPair));
            expect(deadBalance).to.equal(1);
            expect(teamBalance).to.equal(5);
            expect(lotteryBalance).to.equal(1);
            expect(address3Balance).to.equal(900);
            expect(pairBalance).to.be.within(1092.9, 1093);
        });
    });
});
