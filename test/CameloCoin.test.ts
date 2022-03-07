import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CameloCoin, CameloCoin__factory } from "../typechain";
import { BigNumber } from "ethers";

describe ("CameloCoin", function(){
    let owner = SignerWithAddress;
    let address1 = SignerWithAddress;
    let address2 = SignerWithAddress;
    let contract = CameloCoin;

    before(async function () {
        [owner, address1, address2] = await ethers.getSigners();
        
    });

    before(async function () {
        let contractFactory = <CameloCoin__factory>await ethers.getContractFactory("CameloCoin");
        contract = await contractFactory.deploy();
        contract = await contract.deployed();

        
    });

    it("Should have the correct name", async function () {
        expect((await contract.name())).to.equal("Camelo Coin");
        expect((await contract.symbol())).to.equal("CMC");
        expect(ethers.utils.formatEther(await contract.balaceOf(owner.address))).to.equal(BigNumber.from("10000000.0"));
        
    });

    it("The admin should be able to withdraw funds that user transfered wrongly", async function() {
        await contract.transfer(address1.address, 1);

        contract = contract.connect(address1);

        await contract.transfer(contract.address, 1);

        await expect(contract.withdrawERC20(contract.address, owner.address, 1)).to.be.revertedWith("AccessControl: account " + address1.address.toLowerCase() + " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        contract = contract.connect(owner);
        await contract.withdrawERC20(contract.address, owner.address, 1);
        await expect(contract.withdrawERC20(contract.address, owner.address, 1)).to.be.revertedWith("You are trying to withdraw more funds than available");

    })
});

