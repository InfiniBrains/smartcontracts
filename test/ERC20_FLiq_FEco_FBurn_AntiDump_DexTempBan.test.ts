/* eslint-disable camelcase */

import { expect } from "chai";
import { ethers, network, waffle } from "hardhat";
import { ERC20FLiqFEcoFBurnAntiDumpDexTempBan, ERC20FLiqFEcoFBurnAntiDumpDexTempBan__factory } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, utils } from "ethers";
import { expandTo9Decimals } from "./shared/utilities";
import { abi } from "@uniswap/v2-periphery/build/UniswapV2Router02.json";

describe.only("ERC20FLiqFEcoFBurnAntiDumpDexTempBan", function () {
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
        contract = await ERC20Factory.deploy("Test", "ERT", 1000000000);
        contract = await contract.deployed();
    });

    /*
    it("Should be constructed properly", async function () {
        expect(await contract.name()).to.equal("Test");
        expect(await contract.symbol()).to.equal("ERT");
        expect(await contract.totalSupply()).to.equal(
        utils.parseUnits("1000000000", 9).toString()
        );
        expect(await contract.decimals()).to.equal(9);
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
    */
});