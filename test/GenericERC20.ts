import { expect } from "chai";
import { ethers, network, waffle } from "hardhat";
import {GenericERC20, GenericERC20__factory, UltimateERC20, UltimateERC20__factory} from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, utils } from "ethers";
import { expandTo9Decimals } from "./shared/utilities";
import { abi } from "@uniswap/v2-periphery/build/UniswapV2Router02.json";

describe("UltimateCoin", function () {
    const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
    let contract: GenericERC20;
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
        const factory = <GenericERC20__factory>(
            await ethers.getContractFactory("GenericERC20")
        );
        contract = await factory.deploy();
        contract = await contract.deployed();
    });

    it("Check gas price",async function(){
        console.log("erc20 without fees");
        console.log(await contract
            .connect(owner).estimateGas
            .transfer(address1.address, expandTo9Decimals("500")));
    });
});