import { expect } from "chai";
import { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {FabricaDeGeniosCoin, FabricaDeGeniosCoin__factory} from "../typechain";
import {BigNumber} from "ethers";

describe("Fabrica de Genios", function () {
    let owner: SignerWithAddress;
    let address1: SignerWithAddress;
    let address2: SignerWithAddress;
    let contract: FabricaDeGeniosCoin;

    before(async function () {
        [owner, address1, address2] = await ethers.getSigners();
    });

    beforeEach(async function () {
        let contractFactory = <FabricaDeGeniosCoin__factory>await ethers.getContractFactory("FabricaDeGeniosCoin");
        contract = await contractFactory.deploy();
        contract = await contract.deployed();
    });

    it("Should have the correct name and total supply", async function () {
        expect((await contract.name())).to.equal("Fabrica de Genios Coin");
        expect((await contract.symbol())).to.equal("FGC");
        expect( ethers.utils.formatEther(await contract.balanceOf(owner.address))).to.equal("1000000000.0");
    });

    it("The admin should be able to withdraw funds that user transfered wrongly", async function () {
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
});
