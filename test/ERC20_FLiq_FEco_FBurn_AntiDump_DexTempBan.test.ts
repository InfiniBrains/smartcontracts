/* eslint-disable camelcase */

import { expect } from "chai";
import { ethers, network, waffle } from "hardhat";
import { ERC20FLiqFEcoFBurnAntiDumpDexTempBan, ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, utils } from "ethers";
import { expandTo9Decimals, expandTo18Decimals } from "./shared/utilities";
import { abi } from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import busdAbi from "./shared/busd.json";

// ATTENTION! do not commit the line below!! You should put only for your tests only!
//describe.only("ERC20FLiqFEcoFBurnAntiDumpDexTempBan", function () {
describe("ERC20FLiqFEcoFBurnAntiDumpDexTempBan", function () {
    const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
    const BUSD_ADDRESS = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
    let contract: ERC20FLiqFEcoFBurnAntiDumpDexTempBan;
    let busdContract: Contract;
    let busdHotWalletAddress: string = '0x8894e0a0c962cb723c1976a4421c95949be2d4e3';
    let busdHotWallet: SignerWithAddress;
    let owner: SignerWithAddress;
    let address1: SignerWithAddress;
    let address2: SignerWithAddress;
    let address3: SignerWithAddress;
    let address4: SignerWithAddress;
    let address5: SignerWithAddress;

    before(async function () {
        [owner, address1, address2, address3, address4, address5] =
        await ethers.getSigners();

        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [busdHotWalletAddress],
        });
        busdHotWallet = await ethers.getSigner(busdHotWalletAddress);

        busdContract = new ethers.Contract(BUSD_ADDRESS, busdAbi, busdHotWallet);
    });

    beforeEach(async function () {
        const ERC20Factory = <ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory>(
            await ethers.getContractFactory("ERC20FLiqFEcoFBurnAntiDumpDexTempBan")
        );
        contract = await ERC20Factory.deploy("Test", "ERT", expandTo18Decimals(1000000000));
        contract = await contract.deployed();
    });

    it("Should be constructed properly", async function () {
        let totalSupply = await contract.totalSupply()
        expect(await contract.name()).to.equal("Test");
        expect(await contract.symbol()).to.equal("ERT");
        expect(totalSupply).to.equal(
            expandTo18Decimals(1000000000).toString()
        );
        expect(await contract.decimals()).to.equal(18);
        expect(await contract.balanceOf(owner.address)).to.equal(
            totalSupply
        );

        expect(
        await contract.isExcludedFromFees(await contract.DEAD_ADDRESS())
        ).to.equal(true);

        expect(await contract.isExcludedFromFees(await contract.owner())).to.equal(
        true
        );

        console.log("totalSupply:", totalSupply);
    });

    it("Should be able to create a new pair", async function () {
        //IT HAS ALREADY BEEN CREATED ON CONSTRUCTOR
        /*const tx = await contract.addNewPair(
            "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
        ); // BUSD address
        const receipt = await tx.wait();
        const newPair: string = utils.defaultAbiCoder.decode(
            ["address"],
            receipt.logs[2].topics[2]
        )[0];

        expect(await contract.automatedMarketMakerPairs(newPair)).to.equal(true);*/
        await expect(
            contract.addNewPair(BUSD_ADDRESS)
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
        await contract.setLiquidityFee(0);

        await contract
            .connect(address1)
            .transfer(address2.address, expandTo9Decimals("0.9"));

        // expect the burn address have the tokens
        expect(await contract.balanceOf(address2.address)).to.equal(
            expandTo9Decimals("0.9")
        );
    });

    describe("Fees", function () {
        beforeEach(async function () {
            await contract.setBurnFee(0);
            await contract.setEcosystemFee(0);
            await contract.setLiquidityFee(0);

            await contract
                .connect(owner)
                .transfer(address1.address, expandTo9Decimals("1"));
        });


        describe("Liquidity fee", function () {
            const ROUTER_ADDRESS = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
            let router: Contract;

            before(async function () {
                router = new ethers.Contract(ROUTER_ADDRESS, abi, owner);
            });

            beforeEach(async function () {
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

                await contract.setLiquidityFee(1000);

                await contract.transfer(address1.address, expandTo9Decimals("510"));
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
        console.log("balanceBusdOwner", balanceBusdOwner);
        expect(balanceBusdOwner).to.equal(expandTo18Decimals(1000000));
    });

    // procurar como adicionar BUSD para cá
    /*
    it("Should be able to create a new pair", async function () {
        await contract._swapTokensForBNB(100);
    });
    */
});