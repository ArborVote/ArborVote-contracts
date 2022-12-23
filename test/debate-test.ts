import {ethers} from 'hardhat';
import {Contract, BigNumber} from 'ethers';
import {expect} from 'chai';

function toBytes(string: string) {
  return ethers.utils.formatBytes32String(string);
}

describe('DebateFactory', function () {
  let debates: Contract;
  let phases: Contract;
  let users: Contract;
  let editing: Contract;
  let voting: Contract;
  let tallying: Contract;
  let utilsLib: Contract;
  let arborVote: Contract;

  let mockProofOfHumanity: Contract;
  let mockERC20: Contract;
  let mockArbitrator: Contract;
  let sender: string;

  beforeEach(async function () {
    sender = await (await ethers.getSigners())[0].getAddress();

    const UtilsLib = await ethers.getContractFactory('UtilsLib');
    utilsLib = await UtilsLib.deploy();
    await utilsLib.deployed();

    const MockProofOfHumanity = await ethers.getContractFactory(
      'MockProofOfHumanity'
    );
    mockProofOfHumanity = await MockProofOfHumanity.deploy();
    await mockProofOfHumanity.deployed();

    const MockArbitrator = await ethers.getContractFactory('MockArbitrator');
    mockArbitrator = await MockArbitrator.deploy();
    await mockArbitrator.deployed();

    const ArborVote = await ethers.getContractFactory('ArborVote', {
      libraries: {
        UtilsLib: utilsLib.address,
      },
    });
    arborVote = await ArborVote.deploy();
    await arborVote.deployed();

    const MockERC20 = await ethers.getContractFactory('MockERC20');
    mockERC20 = await MockERC20.deploy(1000, sender);
    await mockERC20.deployed();
    await mockERC20.approve(arborVote.address, 1000);
  });

  describe('initialize', async function () {
    it('initializes the contract', async function () {
      await expect(arborVote.initialize(mockProofOfHumanity.address)).to.not.be
        .reverted;
    });
  });

  describe('createDebate', async function () {
    beforeEach(async function () {
      await arborVote.initialize(mockProofOfHumanity.address);
    });

    it('creates a debate and allows to join', async function () {
      const thesis = toBytes('We should do XYZ');

      const timeUnit = 1 * 60; // 1 minute
      const id = await arborVote.callStatic.createDebate(thesis, timeUnit);
      expect(id).to.equal(0);

      let tx = await arborVote.createDebate(thesis, timeUnit);
      let rc = await tx.wait();

      tx = await arborVote.join(id);
      tx.wait();

      await arborVote.addArgument(
        0,
        0,
        toBytes('This is a good idea.'),
        true,
        51
      );

      // suppose the current block has a timestamp of 01:00 PM
      await ethers.provider.send('evm_increaseTime', [10 * timeUnit]);
      await ethers.provider.send('evm_mine', []); // this one will have 02:00 PM as its timestamp

      tx = await arborVote.updatePhase(id);
      rc = await tx.wait();
      await ethers.provider.send('evm_mine', []);

      console.log('here', await arborVote.debateResult(id));
    });
  });
});
