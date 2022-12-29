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
  const thesisContent = toBytes('We should do XYZ');
  const proArgumentContent = toBytes('This is a good idea.');
  const conArgumentContent = toBytes('This is a bad idea.');
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
      debateId = await arborVote.callStatic.createDebate(
        thesisContent,
        timeUnit
      );
      await arborVote.createDebate(thesisContent, timeUnit);
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

    it('increments the debate ID', async function () {
      debateId = await arborVote.callStatic.createDebate(
        thesisContent,
        timeUnit
      );
      expect(debateId).to.eq(0);
      await arborVote.createDebate(thesisContent, timeUnit);

      debateId = await arborVote.callStatic.createDebate(
        thesisContent,
        timeUnit
      );
      expect(debateId).to.eq(1);
    });

    it('initializes the phase data', async function () {
      debateId = await arborVote.callStatic.createDebate(
        thesisContent,
        timeUnit
      );
      await arborVote.createDebate(thesisContent, timeUnit);

      let currentTime = await getTime();
      let phaseData = convertToStruct(await arborVote.phases(debateId));

      expect(phaseData.currentPhase).to.eq(Phase.Editing);
      expect(phaseData.timeUnit).to.eq(timeUnit);
      expect(phaseData.editingEndTime).to.eq(currentTime + 7 * timeUnit);
      expect(phaseData.votingEndTime).to.eq(currentTime + 10 * timeUnit);
    });

    it('initializes the root argument', async function () {
      debateId = await arborVote.callStatic.createDebate(
        thesisContent,
        timeUnit
      );
      await arborVote.createDebate(thesisContent, timeUnit);

      const rootArgument = convertToStruct(
        await arborVote.getArgument(debateId, rootArgumentId)
      );
      expect(rootArgument.contentURI).to.eq(thesisContent);

      expect(rootArgument.pro).to.eq(0);
      expect(rootArgument.con).to.eq(0);
      expect(rootArgument.const).to.eq(0);
      expect(rootArgument.vote).to.eq(0);
      expect(rootArgument.fees).to.eq(0);

      expect(rootArgument.creator).to.eq(signers[0].address);
      expect(rootArgument.state).to.eq(State.Final);
      expect(rootArgument.finalizationTime).to.eq(await getTime());

      expect(rootArgument.isSupporting).to.eq(false);
      expect(rootArgument.parentArgumentId).to.eq(0);
      expect(rootArgument.childsVote).to.eq(0);

      expect(await arborVote.getLeafArgumentIds(debateId)).to.be.empty;
      expect(await arborVote.getDisputedArgumentIds(debateId)).to.be.empty;
    });
  });

  describe('join', async function () {
    beforeEach(async function () {
      await arborVote.initialize(mockProofOfHumanity.address);
      debateId = await arborVote.callStatic.createDebate(
        thesisContent,
        timeUnit
      );
      await arborVote.createDebate(thesisContent, timeUnit);
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

  describe('addArgument', async function () {
    beforeEach(async function () {
      await arborVote.initialize(mockProofOfHumanity.address);
      debateId = await arborVote.callStatic.createDebate(
        thesisContent,
        timeUnit
      );
      await arborVote.createDebate(thesisContent, timeUnit);
      await arborVote.join(debateId);
    });

    it('increments the argument ID', async function () {
      let argumentId = await arborVote.callStatic.addArgument(
        debateId,
        rootArgumentId,
        proArgumentContent,
        true,
        50
      );
      await arborVote.addArgument(
        debateId,
        rootArgumentId,
        proArgumentContent,
        true,
        50
      );
      expect(argumentId).to.equal(1);

      argumentId = await arborVote.callStatic.addArgument(
        debateId,
        rootArgumentId,
        proArgumentContent,
        true,
        50
      );
      expect(argumentId).to.equal(2);
    });

    it('adds a pro argument', async function () {
      await arborVote.addArgument(
        debateId,
        rootArgumentId,
        proArgumentContent,
        true,
        50
      );
      const proArgumentId = 1;
      let currentTime = await getTime();

      const proArgument = convertToStruct(
        await arborVote.getArgument(debateId, proArgumentId)
      );
      expect(proArgument.contentURI).to.eq(proArgumentContent);

      expect(proArgument.pro).to.eq(5);
      expect(proArgument.con).to.eq(5);
      expect(proArgument.const).to.eq(25);
      expect(proArgument.vote).to.eq(10);
      expect(proArgument.fees).to.eq(0);

      expect(proArgument.creator).to.eq(signers[0].address);
      expect(proArgument.state).to.eq(State.Created);
      expect(proArgument.finalizationTime).to.eq(currentTime + timeUnit);

      expect(proArgument.isSupporting).to.eq(true);
      expect(proArgument.parentArgumentId).to.eq(0);
      expect(proArgument.childsVote).to.eq(0);

      expect(await arborVote.getLeafArgumentIds(debateId)).to.be.deep.eq([
        proArgumentId,
      ]);
      expect(await arborVote.getDisputedArgumentIds(debateId)).to.be.empty;
    });

    it('adds a con argument', async function () {
      await arborVote.addArgument(
        debateId,
        rootArgumentId,
        proArgumentContent,
        false,
        50
      );
      const conArgumentId = 1;
      let currentTime = await getTime();

      const conArgument = convertToStruct(
        await arborVote.getArgument(debateId, conArgumentId)
      );
      expect(conArgument.contentURI).to.eq(proArgumentContent);

      expect(conArgument.pro).to.eq(5);
      expect(conArgument.con).to.eq(5);
      expect(conArgument.const).to.eq(25);
      expect(conArgument.vote).to.eq(10);
      expect(conArgument.fees).to.eq(0);

      expect(conArgument.creator).to.eq(signers[0].address);
      expect(conArgument.state).to.eq(State.Created);
      expect(conArgument.finalizationTime).to.eq(currentTime + timeUnit);

      expect(conArgument.isSupporting).to.eq(false);
      expect(conArgument.parentArgumentId).to.eq(0);
      expect(conArgument.childsVote).to.eq(0);

      expect(await arborVote.getLeafArgumentIds(debateId)).to.be.deep.eq([
        conArgumentId,
      ]);
      expect(await arborVote.getDisputedArgumentIds(debateId)).to.be.empty;
    });

    context('arguments with different intial approvals', async function () {
      it('reverts for initial approvals below 50%', async function () {
        const initialApproval = 49;
        await expect(
          arborVote.addArgument(
            debateId,
            rootArgumentId,
            proArgumentContent,
            true,
            initialApproval
          )
        ).to.be.revertedWith(
          customError('InitialApprovalOutOfBounds', 50, initialApproval)
        );
      });

      it('reverts for initial approvals above 100%', async function () {
        const initialApproval = 101;
        await expect(
          arborVote.addArgument(
            debateId,
            rootArgumentId,
            proArgumentContent,
            true,
            initialApproval
          )
        ).to.be.revertedWith(
          customError('InitialApprovalOutOfBounds', 100, initialApproval)
        );
      });

      it('initializes the argument argument with an intial approval of 50%', async function () {
        const initialApproval = 50;
        await arborVote.addArgument(
          debateId,
          rootArgumentId,
          proArgumentContent,
          true,
          initialApproval
        );
        const argumentId = 1;

        const argument = convertToStruct(
          await arborVote.getArgument(debateId, argumentId)
        );
        expect(argument.pro).to.eq(5);
        expect(argument.con).to.eq(5);
        expect(argument.const).to.eq(25);
        expect(argument.vote).to.eq(10);
        expect(argument.fees).to.eq(0);
      });

      it('initializes the argument argument with an intial approval of 80%', async function () {
        const initialApproval = 80;
        await arborVote.addArgument(
          debateId,
          rootArgumentId,
          proArgumentContent,
          true,
          initialApproval
        );
        const argumentId = 1;

        const argument = convertToStruct(
          await arborVote.getArgument(debateId, argumentId)
        );
        expect(argument.pro).to.eq(2);
        expect(argument.con).to.eq(8);
        expect(argument.const).to.eq(16);
        expect(argument.vote).to.eq(10);
        expect(argument.fees).to.eq(0);
      });

      it('initializes the argument argument with an intial approval of 100%', async function () {
        const initialApproval = 100;
        await arborVote.addArgument(
          debateId,
          rootArgumentId,
          proArgumentContent,
          true,
          initialApproval
        );
        const argumentId = 1;

        const argument = convertToStruct(
          await arborVote.getArgument(debateId, argumentId)
        );
        expect(argument.pro).to.eq(0);
        expect(argument.con).to.eq(10);
        expect(argument.const).to.eq(0); // TODO
        expect(argument.vote).to.eq(10);
        expect(argument.fees).to.eq(0);
      });
    });
  });
});
