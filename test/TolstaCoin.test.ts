import { expect } from "chai";
import { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {TolstaCoin, TolstaCoin__factory} from "../typechain";

describe("Tolsta Coin", function () {
    let owner: SignerWithAddress;
    let address1: SignerWithAddress;
    let address2: SignerWithAddress;
    let contract: TolstaCoin;

    before(async function () {
        [owner, address1, address2] = await ethers.getSigners();
    });

    beforeEach(async function () {
        let contractFactory = <TolstaCoin__factory>await ethers.getContractFactory("TolstaCoin");
        contract = await contractFactory.deploy();
        contract = await contract.deployed();
    });

    it("Should have the correct name and total supply. Tolsta Coin.", async function () {
        expect((await contract.name())).to.equal("Tolsta Coin");
        expect((await contract.symbol())).to.equal("TC");
        expect(ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("1000000000.0");
    });

    it("The admin should be able to withdraw funds that user transfered wrongly. Tolsta Coin.", async function () {
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
    });

    it("The admin burn token. Tolsta Coin.", async function () {
        console.log("TOTAL Tolsta Coin " + ethers.utils.formatEther(await contract.balanceOf(owner.address)));
        await expect(contract.burnToken(ethers.utils.parseUnits(String(1000000000), 18))).to.be.revertedWith("50% maximum burn allowed");

        await contract.burnToken(ethers.utils.parseUnits(String(500000000), 18));
        expect(ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("500000000.0");

       
        await contract.burnTeam(ethers.utils.parseUnits(String(200000000), 18));
        expect(ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("300000000.0");
        await expect(contract.burnTeam(ethers.utils.parseUnits(String(600000000), 18))).to.be.revertedWith("You are trying to withdraw more funds than available");

        await contract.transfer(address1.address, ethers.utils.parseUnits(String(200000000), 18));
        contract = contract.connect(address1);
        console.log("TOTAL ADDRESS1  " + ethers.utils.formatEther(await contract.balanceOf(address1.address)));
        await contract.burnFromLiquidity(ethers.utils.parseUnits(String(200000000), 18));
        console.log("TOTAL ADDRESS1 BURN " + ethers.utils.formatEther(await contract.balanceOf(address1.address)));
        await expect(contract.burnFromLiquidity(ethers.utils.parseUnits(String(600000000), 18))).to.be.revertedWith("You are trying to withdraw more funds than available");
        expect(ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("300000000.0");

        console.log("TOTAL Tolsta Coin " + ethers.utils.formatEther(await contract.balanceOf(owner.address)));
    });
});
