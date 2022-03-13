import { expect } from "chai";
import { ethers } from "hardhat";
import {BetCoin, BetCoin__factory} from "../../typechain";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
let contract: BetCoin;
let owner: SignerWithAddress;
let address1: SignerWithAddress;
let address2: SignerWithAddress;
let address3: SignerWithAddress;
let address4: SignerWithAddress;
let address5: SignerWithAddress;


describe("BetCoin", function () {
    before(async function () {
        [owner, address1, address2, address3, address4, address5] = await ethers.getSigners();
    });

    beforeEach(async function () {
        const betcoinFactory = <BetCoin__factory>await ethers.getContractFactory("BetCoinV2");
        contract = await betcoinFactory.deploy();
        contract = await contract.deployed();
        await contract.settransform(true);
        await contract.setEnableContract(true);
        await contract.setTeamWallet(address1.address);
        await contract.setLotteryWallet(address2.address);
    });

    it("Should be able to withdraw funds", async function () {
        const Greeter = await ethers.getContractFactory("Greeter");
        const greeter = await Greeter.deploy("Hello, world!");
        await greeter.deployed();

        expect(await greeter.greet()).to.equal("Hello, world!");

        const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

        // wait until the transaction is mined
        await setGreetingTx.wait();

        expect(await greeter.greet()).to.equal("Hola, mundo!");
    });
});
