import {ethers} from 'hardhat';
import {Contract} from 'ethers';
import {expect} from 'chai';

import {
  customError,
  toBytes,
  convertToStruct,
  getTime,
  advanceTime,
  advanceTimeTo,
} from './test-helpers';

enum Phase {
  Unitialized,
  Editing,
  Voting,
  Finished,
}

enum Role {
  Unassigned,
  Participant,
  Juror,
}

enum State {
  Unitialized,
  Created,
  Final,
  Disputed,
  Invalid,
}

describe('ArborVote', function () {
  let utilsLib: Contract;
  let arborVote: Contract;

  let mockProofOfHumanity: Contract;
  let mockERC20: Contract;
  let mockArbitrator: Contract;
  let sender: string;
  let debateId: number;

  const timeUnit: number = 1 * 60; // 1 minute
  const thesis = toBytes('We should do XYZ');

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

  describe('updatePhase', async function () {
    beforeEach(async function () {
      await arborVote.initialize(mockProofOfHumanity.address);
      debateId = (await arborVote.createDebate(thesis, timeUnit)).value;
    });

    it('reverts for an uninitialized debate', async function () {
      const uninitializedDebateId = 123;
      expect(
        (await arborVote.phases(uninitializedDebateId)).currentPhase
      ).to.eq(Phase.Unitialized);

      await expect(
        arborVote.updatePhase(uninitializedDebateId)
      ).to.be.revertedWith(
        customError('DebateUninitialized', uninitializedDebateId)
      );
    });

    it('advances the phases after the time has passed', async function () {
      let phaseData = convertToStruct(await arborVote.phases(debateId));
      expect(phaseData.currentPhase).to.eq(Phase.Editing);

      await advanceTimeTo(phaseData.editingEndTime);
      await arborVote.updatePhase(debateId);
      expect((await arborVote.phases(debateId)).currentPhase).to.eq(
        Phase.Voting
      );

      await advanceTimeTo(phaseData.votingEndTime);
      await arborVote.updatePhase(debateId);
      expect((await arborVote.phases(debateId)).currentPhase).to.eq(
        Phase.Finished
      );
    });
  });

  describe('createDebate', async function () {
    beforeEach(async function () {
      await arborVote.initialize(mockProofOfHumanity.address);
    });

    it('is uninitialized before a debate is created', async function () {
      debateId = 0;
      let phaseData = convertToStruct(await arborVote.phases(debateId));
      expect(phaseData.currentPhase).to.eq(Phase.Unitialized);
      expect(phaseData.editingEndTime).to.eq(0);
      expect(phaseData.votingEndTime).to.eq(0);
      expect(phaseData.timeUnit).to.eq(0);
    });

    it('initializes the phase data', async function () {
      debateId = (await arborVote.createDebate(thesis, timeUnit)).value;
      expect(debateId).to.equal(0);

      let currentTime = await getTime();
      let phaseData = convertToStruct(await arborVote.phases(debateId));

      expect(phaseData.currentPhase).to.eq(Phase.Editing);
      expect(phaseData.timeUnit).to.eq(timeUnit);
      expect(phaseData.editingEndTime).to.eq(currentTime + 7 * timeUnit);
      expect(phaseData.votingEndTime).to.eq(currentTime + 10 * timeUnit);
    });

    it('creates a debate and allows to join', async function () {
      debateId = await arborVote.callStatic.createDebate(thesis, timeUnit);
      expect(debateId).to.equal(0);

      await arborVote.createDebate(thesis, timeUnit);
      await arborVote.join(debateId);

      await arborVote.addArgument(
        0,
        0,
        toBytes('This is a good idea.'),
        true,
        51
      );
    });
  });
});
