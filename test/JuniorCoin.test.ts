import { expect } from "chai";
import { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {JuniorCoin, JuniorCoin__factory} from "../typechain";

describe("JuniorCoin", function () {
    let owner: SignerWithAddress;
    let address1: SignerWithAddress;
    let address2: SignerWithAddress;
    let contract: JuniorCoin;

    before(async function () {
        [owner, address1, address2] = await ethers.getSigners();
    });

    beforeEach(async function () {
        let contractFactory = <JuniorCoin__factory>await ethers.getContractFactory("JuniorCoin");
        contract = await contractFactory.deploy();
        contract = await contract.deployed();
    });

    it("Should have the correct name and total supply, JuniorCoin", async function () {
        expect((await contract.name())).to.equal("JuniorCoin");
        expect((await contract.symbol())).to.equal("JRC");
        expect( ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("1000000000.0");
    });

    it("The admin should be able to withdraw funds that user transfered wrongly, JuniorCoin", async function () {
        // expect(await address1.sendTransaction({to: contract.address, value: 1})).to.be.revertedWith("function selector was not recognized and there's no fallback nor receive function");
        await contract.transfer(address1.address, 1);

        // swap caller
        contract = contract.connect(address1);

        // execute transfer
        await contract.transfer(contract.address, 1);

        // @ts-ignore
        await expect(contract.withdrawERC20(contract.address, owner.address, 1)).to.be.revertedWith("AccessControl: account " + address1.address.toLowerCase() + " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        // swap caller
        contract = contract.connect(owner);
        await contract.withdrawERC20(contract.address, owner.address, 1);
        await expect(contract.withdrawERC20(contract.address, owner.address, 1)).to.be.revertedWith("You are trying to withdraw more funds than available");

        // transfer devs
        await contract.withdrawTeamDev(ethers.utils.parseUnits(String(500000000), 18));
        expect(ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("500000000.0");

        // transfer marketing
        await contract.withdrawTeamMkt(ethers.utils.parseUnits(String(100000000), 18));
        expect(ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("400000000.0");

        await contract.transfer(address1.address, ethers.utils.parseUnits(String(200000000), 18));
        contract = contract.connect(address1);
        console.log("TOTAL ADDRESS1  " + ethers.utils.formatEther(await contract.balanceOf(address1.address)));
        
        // giveback token 
        await contract.giveback(ethers.utils.parseUnits(String(200000000), 18));
        console.log("TOTAL ADDRESS1 " + ethers.utils.formatEther(await contract.balanceOf(address1.address)));
       
        await expect(contract.giveback(ethers.utils.parseUnits(String(600000000), 18))).to.be.revertedWith("You are trying to withdraw more funds than available");
        expect(ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("400000000.0");
    });
});
