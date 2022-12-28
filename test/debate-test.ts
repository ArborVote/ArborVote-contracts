import {ethers} from 'hardhat';
import {Contract} from 'ethers';
import {expect} from 'chai';

import {
  customError,
  toBytes,
  convertToStruct,
  getTime,
  advanceTimeTo,
} from './test-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';

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
  let signers: SignerWithAddress[];
  let debateId: number;

  const timeUnit: number = 1 * 60; // 1 minute
  const thesis = toBytes('We should do XYZ');
  const rootArgumentId = 0;

  beforeEach(async function () {
    signers = await ethers.getSigners();

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
    mockERC20 = await MockERC20.deploy(1000, signers[0].address);
    await mockERC20.deployed();
    await mockERC20.approve(arborVote.address, 1000);
  });

  describe('initialize', async function () {
    it('initializes the contract', async function () {
      await expect(arborVote.initialize(mockProofOfHumanity.address)).to.not.be
        .reverted;
    });
  });

  describe('advancePhase', async function () {
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
        arborVote.advancePhase(uninitializedDebateId)
      ).to.be.revertedWith(
        customError('DebateUninitialized', uninitializedDebateId)
      );
    });

    it('advances the phases after the time has passed', async function () {
      let phaseData = convertToStruct(await arborVote.phases(debateId));
      expect(phaseData.currentPhase).to.eq(Phase.Editing);

      await advanceTimeTo(phaseData.editingEndTime);
      await arborVote.advancePhase(debateId);
      expect((await arborVote.phases(debateId)).currentPhase).to.eq(
        Phase.Voting
      );

      await advanceTimeTo(phaseData.votingEndTime);
      await arborVote.advancePhase(debateId);
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

    it('initializes the root argument', async function () {
      debateId = (await arborVote.createDebate(thesis, timeUnit)).value;
      expect(debateId).to.equal(0);

      const rootArgument = convertToStruct(
        await arborVote.getArgument(debateId, rootArgumentId)
      );
      expect(rootArgument.contentURI).to.eq(thesis);

      const market = convertToStruct(rootArgument.market);
      expect(market.pro).to.eq(0);
      expect(market.con).to.eq(0);
      expect(market.const).to.eq(0);
      expect(market.vote).to.eq(0);
      expect(market.fees).to.eq(0);

      const metadata = convertToStruct(rootArgument.metadata);
      expect(metadata.creator).to.eq(signers[0].address);
      expect(metadata.state).to.eq(State.Final);
      expect(metadata.finalizationTime).to.eq(await getTime());

      expect(metadata.isSupporting).to.eq(false);
      expect(metadata.parentArgumentId).to.eq(0);
      expect(metadata.childsVote).to.eq(0);

      expect(await arborVote.getLeafArgumentIds(debateId)).to.be.empty;
      expect(await arborVote.getDisputedArgumentIds(debateId)).to.be.empty;
    });
  });

  describe('join', async function () {
    beforeEach(async function () {
      await arborVote.initialize(mockProofOfHumanity.address);
      debateId = (await arborVote.createDebate(thesis, timeUnit)).value;
    });

    it('joins a debate', async function () {
      expect(await arborVote.getUserRole(debateId, signers[0].address)).to.eq(
        Role.Unassigned
      );
      expect(await arborVote.getUserTokens(debateId, signers[0].address)).to.eq(
        0
      );
      let shares = convertToStruct(
        await arborVote.getUserShares(
          debateId,
          rootArgumentId,
          signers[0].address
        )
      );
      expect(shares.pro).to.eq(0);
      expect(shares.con).to.eq(0);

      await arborVote.join(debateId);

      expect(await arborVote.getUserRole(debateId, signers[0].address)).to.eq(
        Role.Participant
      );
      expect(await arborVote.getUserTokens(debateId, signers[0].address)).to.eq(
        await arborVote.INITIAL_TOKENS()
      );
      shares = convertToStruct(
        await arborVote.getUserShares(
          debateId,
          rootArgumentId,
          signers[0].address
        )
      );
      expect(shares.pro).to.eq(0);
      expect(shares.con).to.eq(0);
    });

    it('reverts if the user has no valid identity proof', async function () {
      await mockProofOfHumanity.deny(signers[0].address);

      await expect(arborVote.join(debateId)).to.be.revertedWith(
        customError('IdentityProofInvalid')
      );
    });
  });
});
