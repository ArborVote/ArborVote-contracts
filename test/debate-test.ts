import {ethers} from "hardhat";
import {Contract, BigNumber} from "ethers";
import chai from "chai";

describe("DebateFactory", function () {
    let debates: Contract;
    let phases: Contract;
    let users: Contract;
    let editing: Contract;
    let voting: Contract;
    let tallying: Contract;
    let utilsLib: Contract;

    let mockProofOfHumanityContract: Contract;
    let mockERC20Contract: Contract;
    let mockArbitratorContract: Contract
    let sender: string;

    beforeEach(async function () {
        sender = await (await ethers.getSigners())[0].getAddress();

        const UtilsLib = await ethers.getContractFactory("UtilsLib");
        utilsLib = await UtilsLib.deploy();
        await utilsLib.deployed();

        const Debates = await ethers.getContractFactory("Debates", {libraries: {UtilsLib: utilsLib.address}});
        const Phases = await ethers.getContractFactory("Phases");
        const Users = await ethers.getContractFactory("Users");
        const Editing = await ethers.getContractFactory("Editing", {libraries: {UtilsLib: utilsLib.address}});
        const Voting = await ethers.getContractFactory("Voting", {libraries: {UtilsLib: utilsLib.address}});
        const Tallying = await ethers.getContractFactory("Tallying", {libraries: {UtilsLib: utilsLib.address}});

        debates = await Debates.deploy();
        phases = await Phases.deploy();
        users = await Users.deploy();
        editing = await Editing.deploy();
        voting = await Voting.deploy();
        tallying = await Tallying.deploy();

        await debates.deployed();
        await phases.deployed();
        await users.deployed();
        await editing.deployed();
        await voting.deployed();
        await tallying.deployed();

        const MockProofOfHumanity = await ethers.getContractFactory("MockProofOfHumanity");
        mockProofOfHumanityContract = await MockProofOfHumanity.deploy();
        await mockProofOfHumanityContract.deployed();

        const MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20Contract = await MockERC20.deploy(1000, sender);
        await mockERC20Contract.deployed();

        const MockArbitrator = await ethers.getContractFactory("MockArbitrator");
        mockArbitratorContract = await MockArbitrator.deploy();
        await mockArbitratorContract.deployed();
    });

    it("Debate initialization", async function () {
        const ArborVote = await ethers.getContractFactory("ArborVote");
        const arborVote = await ArborVote.deploy();
        await arborVote.deployed();

        await arborVote.initialize(
            phases.address,
            debates.address,
            users.address,
            editing.address,
            voting.address,
            tallying.address,
            mockProofOfHumanityContract.address
        );

        // Approve ERC token
        await mockERC20Contract.approve(await arborVote.address, 1000);
        const ipfsHash = ethers.utils.formatBytes32String("test");

        const id = await arborVote.createDebate(ipfsHash, 12345);
        await arborVote.join(id.value);
    });
});

