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

    it("Should mint to a different account", async function () {
        // value before should be 0
        expect((await contract.balanceOf(address1.address)).toString()).to.equal(BigNumber.from(0).toString());

        // mint
        await contract.mint(address1.address, 1);

        // value after should be 1
        expect((await contract.balanceOf(address1.address)).toString()).to.equal(BigNumber.from(1).toString());
    });

    it("General user should not be able to mint", async function () {
        // value before should be 0
        expect((await contract.balanceOf(address1.address)).toString()).to.equal(BigNumber.from(0).toString());

        // should fail
        await expect(contract.connect(address1).mint(address1.address,1)).to.be.revertedWith('ERC20PresetMinterPauser: must have minter role to mint');

        expect((await contract.balanceOf(address1.address)).toString()).to.equal(BigNumber.from(0).toString());
    });

    it("Should have the correct name", async function () {
        expect((await contract.name())).to.equal("Fabrica de Genios Coin");
        expect((await contract.symbol())).to.equal("FGC");
    });
});
