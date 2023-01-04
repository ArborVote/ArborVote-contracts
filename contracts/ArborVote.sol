//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

import "./interfaces/IArbitrator.sol";
import "./interfaces/IArbitrable.sol";
import "./interfaces/IProofOfHumanity.sol";
import "./utils/UtilsLib.sol";
import "./Types.sol";

contract ArborVote is IArbitrable {
    using UtilsLib for uint16[];
    using UtilsLib for uint32;
    using UtilsLib for uint64;
    using UtilsLib for int64;
    using SafeERC20 for ERC20;
    using SafeCast for uint256;
    using Counters for Counters.Counter;
    using DebateLib for Debate;

    uint16 internal constant MAX_ARGUMENTS = type(uint16).max;

    uint32 internal constant DEBATE_DEPOSIT = 10;
    uint32 internal constant FEE_PERCENTAGE = 5;
    uint32 public constant INITIAL_TOKENS = 100;

    int64 internal constant MIX_VAL = type(int64).max / 2;
    int64 internal constant MIX_MAX = type(int64).max;

    IProofOfHumanity private poh; // PoH mainnet: 0x1dAD862095d40d43c2109370121cf087632874dB

    Counters.Counter private debatesCounter;
    mapping(uint256 => Debate) public debates;
    mapping(uint256 => mapping(uint16 => uint256)) public disputes;
    mapping(uint256 => mapping(address => User)) public users;
    mapping(uint256 => PhaseData) public phases;

    IArbitrator arbitrator;

    /// @notice Emitted when an argument in a debate gets disputed.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param disputeId The ID of the dispute raised.
    /// @param reason The reason for the dispute.
    event DisputeRaised(
        uint256 indexed debateId,
        uint16 indexed argumentId,
        uint256 disputeId,
        bytes reason
    );

    /// @notice Emitted when a dispute of an argument in a debate is resolved.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    event DisputeResolved(uint256 indexed debateId, uint16 indexed argumentId, uint256 disputeId);

    /// @notice Emitted when an argument in a debate is updated.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param contentURI The URI pointing to the content of the argument.
    event ArgumentUpdated(
        uint256 indexed debateId,
        uint16 indexed argumentId,
        uint16 indexed parentArgumentId,
        bytes32 contentURI
    );

    /// @notice Emitted when an debater invests vote tokens in an argument in a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param investor The address of the investor.
    /// @param data The data of the investment that was made.
    event Invested(
        uint256 indexed debateId,
        uint16 indexed argumentId,
        address indexed investor,
        InvestmentData data
    );

    /// @notice Emitted when the impact of an argument in a debate was calculated.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param impact The impact value of the argument.
    event ArgumentImpactCalculated(
        uint256 indexed debateId,
        uint16 indexed argumentId,
        int64 impact
    );

    /// @notice Thrown if a debate is uninitialized.
    /// @param debateId The ID of the debate.
    error DebateUninitialized(uint256 debateId);

    /// @notice Thrown if the phase of a debate is invalid.
    /// @param expected The expected debate phase.
    /// @param actual The actual debate phase.
    error PhaseInvalid(Phase expected, Phase actual);

    /// @notice Thrown if the state of an argument is invalid.
    /// @param expected The expected argument state.
    /// @param actual The actual argument state.
    error StateInvalid(State expected, State actual);

    /// @notice Thrown if the role of a user is invalid.
    /// @param expected The expected role.
    /// @param actual The actual role.
    error RoleInvalid(Role expected, Role actual);

    /// @notice Thrown if an address is invalid.
    /// @param expected The expected address.
    /// @param actual The actual address.
    error AddressInvalid(address expected, address actual);

    /// @notice Thrown if the identity proof of an account is invalid.
    error IdentityProofInvalid();

    /// @notice Thrown if the time is out of bounds.
    /// @param limit The limit time as a unix timestamp.
    /// @param actual The actual time as a unix timestamp.
    error TimeOutOfBounds(uint32 limit, uint32 actual);

    /// @notice Thrown if initial approval value is out of bounds.
    /// @param limit The limit initial approval value.
    /// @param actual The actual initial approval value.
    error InitialApprovalOutOfBounds(uint32 limit, uint32 actual);

    /// @notice Thrown if the vote token balance is too low.
    /// @param required The required vote tokens.
    /// @param actual The actual vote token balance.
    error InsufficientVoteTokens(uint32 required, uint32 actual);

    /// @notice Thrown if the childs of the argument are not tallied.
    /// @param untalliedChilds The number of untallied childs.
    error ChildsUntallied(uint16 untalliedChilds);

    /// @notice A modifier to restrict functions to only be called if the debate is in a certain phase.
    /// @param _debateId The ID of the debate.
    /// @param _phase The phase of the debate required.
    modifier onlyPhase(uint256 _debateId, Phase _phase) {
        _onlyPhase(_debateId, _phase);
        _;
    }

    /// @notice A modifier to restrict functions to only be called if the debate is not in a certain phase.
    /// @param _debateId The ID of the debate.
    /// @param _phase The phase of the debate excluded.
    modifier excludePhase(uint256 _debateId, Phase _phase) {
        _excludePhase(_debateId, _phase);
        _;
    }

    /// @notice A modifier to restrict functions to only be called if the argument is in a certain state.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument.
    /// @param _state The state of the argument required.
    modifier onlyArgumentState(
        uint256 _debateId,
        uint16 _argumentId,
        State _state
    ) {
        _onlyArgumentState(_debateId, _argumentId, _state);
        _;
    }

    /// @notice A modifier to restrict functions to only be called by the creator of an argument.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument.
    modifier onlyCreator(uint256 _debateId, uint16 _argumentId) {
        _onlyCreator(_debateId, _argumentId);
        _;
    }

    /// @notice A modifier to restrict functions to be only called by accounts holding a certain role.
    /// @param _debateId The ID of the debate.
    /// @param _role The role required.
    modifier onlyRole(uint256 _debateId, Role _role) {
        _onlyRole(_debateId, _role);
        _;
    }

    /// @notice Initializes the contract.
    /// @param _poh The proof of humanity registry contract.
    function initialize(IProofOfHumanity _poh) external {
        poh = _poh;
    }

    /// @notice Returns an argument from a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument.
    /// @return The argument queried.
    function getArgument(
        uint256 _debateId,
        uint16 _argumentId
    ) external view returns (Argument memory) {
        return debates[_debateId].arguments[_argumentId];
    }

    /// @notice Returns the leaf argument IDs of a debate.
    /// @param _debateId The ID of the debate.
    /// @return The leaf argument IDs.
    function getLeafArgumentIds(uint256 _debateId) external view returns (uint16[] memory) {
        return debates[_debateId].leafArgumentIds;
    }

    /// @notice Returns the leaf argument IDs of a debate.
    /// @param _debateId The ID of the debate.
    /// @return The disputed argument IDs.
    function getDisputedArgumentIds(uint256 _debateId) external view returns (uint16[] memory) {
        return debates[_debateId].disputedArgumentIds;
    }

    /// @notice Returns the role of a user in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _account The account of the user.
    /// @return The user role.
    function getUserRole(uint256 _debateId, address _account) external view returns (Role) {
        return users[_debateId][_account].role;
    }

    /// @notice Returns the tokens of a user in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _account The account of the user.
    /// @return The user role.
    function getUserTokens(uint256 _debateId, address _account) external view returns (uint32) {
        return users[_debateId][_account].tokens;
    }

    /// @notice Returns the shares of a user of an argument in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _account The account of the user.
    /// @return The user role.
    function getUserShares(
        uint256 _debateId,
        uint16 _argumentId,
        address _account
    ) external view returns (Shares memory) {
        return users[_debateId][_account].shares[_argumentId];
    }

    /// @notice Creates a new debate.
    /// @param _contentURI The URI pointing to the content of the debate thesis.
    /// @param _timeUnit The time unit of the debate determining the editing and voting times.
    function createDebate(
        bytes32 _contentURI,
        uint32 _timeUnit
    )
        external
        onlyArgumentState(debatesCounter.current(), 0, State.Unitialized)
        returns (uint256 debateId)
    {
        debateId = debatesCounter.current();
        debatesCounter.increment();

        // Create the root Argument
        Debate storage newDebate_ = debates[debateId];
        Argument storage rootArgument_ = newDebate_.arguments[0];

        // Create the root argument of the tree
        rootArgument_.contentURI = _contentURI;

        rootArgument_.creator = msg.sender;
        rootArgument_.finalizationTime = block.timestamp.toUint32();
        rootArgument_.state = State.Final;

        // Store the phase related data
        PhaseData storage phaseData_ = phases[debateId];
        phaseData_.currentPhase = Phase.Editing;
        phaseData_.timeUnit = _timeUnit;
        phaseData_.editingEndTime = block.timestamp.toUint32() + 7 * _timeUnit;
        phaseData_.votingEndTime = block.timestamp.toUint32() + 10 * _timeUnit;

        // increment counters
        newDebate_.incrementArgumentCounter();

        emit ArgumentUpdated({
            debateId: debateId,
            argumentId: 0,
            parentArgumentId: 0,
            contentURI: _contentURI
        });
    }

    /// @notice Advances the phase of the debate.
    /// @param _debateId The ID of the debate.
    function advancePhase(uint256 _debateId) public {
        PhaseData storage phaseData_ = phases[_debateId];

        if (phaseData_.currentPhase == Phase.Unitialized) {
            revert DebateUninitialized({debateId: _debateId});
        }

        uint32 currentTime = block.timestamp.toUint32();

        if (currentTime > phaseData_.votingEndTime && phaseData_.currentPhase != Phase.Finished) {
            phaseData_.currentPhase = Phase.Finished;
        } else if (
            currentTime > phaseData_.editingEndTime && phaseData_.currentPhase != Phase.Voting
        ) {
            phaseData_.currentPhase = Phase.Voting;
        }
    }

    /// @notice Join a debate and receive debate tokens.
    /// @param _debateId The ID of the debate.
    function join(
        uint256 _debateId
    ) external excludePhase(_debateId, Phase.Finished) onlyRole(_debateId, Role.Unassigned) {
        if (!poh.isRegistered(msg.sender)) {
            revert IdentityProofInvalid();
        } // not failsafe - takes 3.5 days to switch address

        User storage user_ = users[_debateId][msg.sender];

        user_.role = Role.Participant;
        user_.tokens = INITIAL_TOKENS;
    }

    /// @notice Returns the outcome of the debate.
    /// @param _debateId The ID of the debate.
    /// @return approved Whether the debate approved the root thesis or not.
    function outcome(uint256 _debateId) external view returns (bool approved) {
        if (phases[_debateId].currentPhase != Phase.Finished)
            revert PhaseInvalid({expected: Phase.Finished, actual: phases[_debateId].currentPhase});

        approved = debates[_debateId].arguments[0].childsImpact > 0;
    }

    /// @notice Finalizes an argument of a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to be finalized.
    function finalizeArgument(
        uint256 _debateId,
        uint16 _argumentId
    ) public onlyArgumentState(_debateId, _argumentId, State.Created) {
        Argument storage argument_ = debates[_debateId].arguments[_argumentId];

        uint32 currentTime = block.timestamp.toUint32();

        if (argument_.finalizationTime > currentTime) {
            revert TimeOutOfBounds({limit: currentTime, actual: argument_.finalizationTime});
        }

        argument_.state = State.Final;
    }

    /// @notice Adds an argument below a parent argument with a certain initial approval.
    /// @param _debateId The ID of the debate.
    /// @param _parentArgumentId The ID of the argument to be finalized.
    /// @param _contentURI The URI pointing to the argument content.
    /// @param _isSupporting Whether the argument supports or opposes the parent argument.
    /// @param _initialApproval The initial approval of the argument.
    /// @dev This requires the argument to not be non-final.
    function addArgument(
        uint256 _debateId,
        uint16 _parentArgumentId,
        bytes32 _contentURI,
        bool _isSupporting,
        uint32 _initialApproval
    )
        public
        onlyRole(_debateId, Role.Participant)
        onlyArgumentState(_debateId, _parentArgumentId, State.Final)
        returns (uint16 newArgumentId)
    {
        User storage user_ = users[_debateId][msg.sender];

        if (_initialApproval < 50) {
            revert InitialApprovalOutOfBounds({limit: 50, actual: _initialApproval});
        }
        if (_initialApproval > 100) {
            revert InitialApprovalOutOfBounds({limit: 100, actual: _initialApproval});
        }

        if (user_.tokens < DEBATE_DEPOSIT) {
            revert InsufficientVoteTokens({required: DEBATE_DEPOSIT, actual: user_.tokens});
        }

        // initialize market
        Debate storage debate_ = debates[_debateId];

        user_.tokens -= DEBATE_DEPOSIT;

        // Create new argument
        newArgumentId = _createArgument(
            _debateId,
            _parentArgumentId,
            _contentURI,
            _isSupporting,
            _initialApproval
        );

        // Update parent
        debate_.arguments[_parentArgumentId].untalliedChilds++;

        // Update the debate's leaf arguments if this is not the root argument
        if (_parentArgumentId != 0) {
            debate_.leafArgumentIds.removeByValue(_parentArgumentId);
        }
        debate_.leafArgumentIds.push(newArgumentId);

        emit ArgumentUpdated({
            debateId: _debateId,
            argumentId: newArgumentId,
            parentArgumentId: _parentArgumentId,
            contentURI: _contentURI
        });
    }

    /// @notice Moves an argument below a new parent argument.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to be moved.
    /// @param _newParentArgumentId The ID of the new parent argument.
    function moveArgument(
        uint256 _debateId,
        uint16 _argumentId,
        uint16 _newParentArgumentId
    )
        external
        onlyPhase(_debateId, Phase.Editing)
        onlyCreator(_debateId, _argumentId)
        onlyArgumentState(_debateId, _argumentId, State.Created)
    {
        Debate storage debate_ = debates[_debateId];
        Argument storage movedArgument_ = debate_.arguments[_argumentId];

        // change old parent's argument state
        uint16 oldParentArgumentId = movedArgument_.parentArgumentId;
        _updateParentAfterChildRemoval(_debateId, oldParentArgumentId);

        // change argument state
        movedArgument_.parentArgumentId = _newParentArgumentId;

        // change new parent argument state
        debate_.arguments[_newParentArgumentId].untalliedChilds++;

        emit ArgumentUpdated({
            debateId: _debateId,
            argumentId: _argumentId,
            parentArgumentId: _newParentArgumentId,
            contentURI: movedArgument_.contentURI
        });
    }

    /// @notice Moves an argument below a new parent argument.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to be moved.
    /// @param _contentURI The URI pointing to the argument content.
    function alterArgument(
        uint256 _debateId,
        uint16 _argumentId,
        bytes32 _contentURI
    )
        external
        onlyPhase(_debateId, Phase.Editing)
        onlyCreator(_debateId, _argumentId)
        onlyArgumentState(_debateId, _argumentId, State.Created)
    {
        uint32 newFinalizationTime = block.timestamp.toUint32() + phases[_debateId].timeUnit;

        if (newFinalizationTime > phases[_debateId].editingEndTime) {
            revert TimeOutOfBounds({
                limit: phases[_debateId].editingEndTime,
                actual: newFinalizationTime
            });
        }

        Argument storage alteredArgument_ = debates[_debateId].arguments[_argumentId];
        alteredArgument_.finalizationTime = newFinalizationTime;
        alteredArgument_.contentURI = _contentURI;

        emit ArgumentUpdated({
            debateId: _debateId,
            argumentId: _argumentId,
            parentArgumentId: alteredArgument_.parentArgumentId,
            contentURI: _contentURI
        });
    }

    /// @notice Raises a dispute for an argument in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    /// @param _reason The reason for raising the dispute.
    /// @return disputeId The ID of the dispute.
    function raiseDispute(
        uint256 _debateId,
        uint16 _argumentId,
        bytes calldata _reason
    )
        external
        onlyPhase(_debateId, Phase.Editing)
        onlyArgumentState(_debateId, _argumentId, State.Final)
        returns (uint256 disputeId)
    {
        // create dispute
        disputeId = _createDispute(_debateId, _argumentId);

        // submit evidence
        _submitEvidence(
            _debateId,
            _argumentId,
            disputeId,
            debates[_debateId].arguments[_argumentId].contentURI,
            _reason
        );

        // state changes
        _addDispute(_debateId, _argumentId, disputeId);

        emit DisputeRaised({
            debateId: _debateId,
            argumentId: _argumentId,
            disputeId: disputeId,
            reason: _reason
        });
    }

    /// @notice Resolves a dispute for an argument in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument being disputed.
    function resolveDispute(
        uint256 _debateId,
        uint16 _argumentId
    )
        external
        onlyPhase(_debateId, Phase.Editing)
        onlyArgumentState(_debateId, _argumentId, State.Disputed)
    {
        uint256 disputeId = disputes[_debateId][_argumentId];

        // fetch ruling
        (address subject, uint256 ruling) = arbitrator.rule(disputeId);
        require(subject == address(this)); // TODO

        Debate storage debate_ = debates[_debateId];

        debate_.disputedArgumentIds.removeByValue(_argumentId);
        if (ruling == 0) {
            debate_.arguments[_argumentId].state = State.Final;
        } else {
            debate_.arguments[_argumentId].state = State.Invalid;
        }

        emit Ruled({arbitrator: arbitrator, disputeId: disputeId, ruling: ruling});
        emit DisputeResolved({debateId: _debateId, argumentId: _argumentId, disputeId: disputeId});
    }

    /// @notice Calculates the amounts of mintable and swapable pro and con shares to be returned for an amount of vote token to be invested.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    /// @param _voteTokenAmount The amount of vote tokens to be invested.
    /// @return investmentData The container containing the calculated amounts.
    function calculateInvestment(
        uint256 _debateId,
        uint16 _argumentId,
        uint32 _voteTokenAmount
    ) public view returns (InvestmentData memory investmentData) {
        investmentData.voteTokensInvested = _voteTokenAmount;

        Argument storage argument_ = debates[_debateId].arguments[_argumentId];

        investmentData.fee = _voteTokenAmount.multipyByFraction(FEE_PERCENTAGE, 100);
        (uint32 proMint, uint32 conMint) = (_voteTokenAmount - investmentData.fee).split(
            argument_.pro,
            argument_.con
        );

        investmentData.proMint = proMint;
        investmentData.conMint = conMint;

        investmentData.proSwap = _calculateProSwap(proMint, conMint);
        investmentData.conSwap = _calculateConSwap(proMint, conMint);
    }

    /// @notice Invests an amount of vote tokens into pro shares.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    /// @param _voteTokenAmount The amount of vote tokens to be invested.
    function investInPro(
        uint256 _debateId,
        uint16 _argumentId,
        uint32 _voteTokenAmount
    ) external onlyPhase(_debateId, Phase.Voting) {
        User storage user_ = users[_debateId][msg.sender];

        if (user_.tokens < _voteTokenAmount) {
            revert InsufficientVoteTokens({required: _voteTokenAmount, actual: user_.tokens});
        }

        user_.tokens -= _voteTokenAmount;

        InvestmentData memory data = calculateInvestment(_debateId, _argumentId, _voteTokenAmount);
        data.conSwap = 0;

        _executeProInvestment(_debateId, _argumentId, data);

        user_.shares[_argumentId].pro += _voteTokenAmount;

        emit Invested({
            debateId: _debateId,
            argumentId: _argumentId,
            investor: msg.sender,
            data: data
        });
    }

    /// @notice Invests an amount of vote tokens into con shares.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    /// @param _voteTokenAmount The amount of vote tokens to be invested.
    function investInCon(
        uint256 _debateId,
        uint16 _argumentId,
        uint32 _voteTokenAmount
    ) external onlyPhase(_debateId, Phase.Voting) {
        User storage user_ = users[_debateId][msg.sender];

        if (user_.tokens < _voteTokenAmount) {
            revert InsufficientVoteTokens({required: _voteTokenAmount, actual: user_.tokens});
        }

        user_.tokens -= _voteTokenAmount;

        InvestmentData memory data = calculateInvestment(_debateId, _argumentId, _voteTokenAmount);
        data.proSwap = 0;

        _executeConInvestment(_debateId, _argumentId, data);

        user_.shares[_argumentId].con += _voteTokenAmount;

        emit Invested({
            debateId: _debateId,
            argumentId: _argumentId,
            investor: msg.sender,
            data: data
        });
    }

    /// @notice Tallies the argument tree of a debate.
    /// @param _debateId The ID of the debate.
    function tallyTree(uint256 _debateId) external onlyPhase(_debateId, Phase.Finished) {
        require(debates[_debateId].disputedArgumentIds.length == 0); // TODO: Remove. Because arguments are guaranteed to be finalized, we can assume this is zero

        uint16[] memory leafArgumentIds = debates[_debateId].leafArgumentIds;

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _tallyNode(_debateId, leafArgumentIds[i]);
        }

        phases[_debateId].currentPhase = Phase.Finished;
    }

    /// @notice An internal function reverting if the debate is not in a certain phase.
    /// @param _debateId The ID of the debate.
    /// @param _phase The phase of the debate required.
    function _onlyPhase(uint256 _debateId, Phase _phase) internal view {
        if (phases[_debateId].currentPhase != _phase)
            revert PhaseInvalid({expected: _phase, actual: phases[_debateId].currentPhase});
    }

    /// @notice An internal function reverting if the debate is not called by the argument creator.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument.
    function _onlyCreator(uint256 _debateId, uint16 _argumentId) internal view {
        address creator = debates[_debateId].arguments[_argumentId].creator;
        if (msg.sender != creator) {
            revert AddressInvalid({expected: creator, actual: msg.sender});
        }
    }

    /// @notice An internal function reverting if the debate if the argument is not in a certain state.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument.
    /// @param _state The state of the argument required.
    function _onlyArgumentState(uint256 _debateId, uint16 _argumentId, State _state) internal view {
        State state = debates[_debateId].arguments[_argumentId].state;
        if (state != _state) {
            revert StateInvalid({expected: _state, actual: state});
        }
    }

    /// @notice An internal function reverting if the debate is not called by an account holding a certain role.
    /// @param _debateId The ID of the debate.
    /// @param _role The role required.
    function _onlyRole(uint256 _debateId, Role _role) internal view {
        Role role = users[_debateId][msg.sender].role;
        if (role != _role) {
            revert RoleInvalid({expected: _role, actual: role});
        }
    }

    /// @notice An internal function reverting if the debate is in a certain phase.
    /// @param _debateId The ID of the debate.
    /// @param _phase The phase of the debate excluded.
    function _excludePhase(uint256 _debateId, Phase _phase) internal view {
        if (phases[_debateId].currentPhase == _phase) {
            revert PhaseInvalid({expected: _phase, actual: phases[_debateId].currentPhase});
        }
    }

    /// @notice Internal function to create an argument below a parent argument with a certain initial approval.
    /// @param _debateId The ID of the debate.
    /// @param _parentArgumentId The ID of the parent argument.
    /// @param _contentURI The URI pointing to the argument content.
    /// @param _isSupporting Whether the argument supports or opposes the parent argument.
    /// @param _initialApproval The initial approval of the argument.
    /// @return newArgumentId The ID of the created argument.
    function _createArgument(
        uint256 _debateId,
        uint16 _parentArgumentId,
        bytes32 _contentURI,
        bool _isSupporting,
        uint32 _initialApproval
    ) internal returns (uint16 newArgumentId) {
        Debate storage debate_ = debates[_debateId];

        newArgumentId = debate_.getArgumentsCount();
        debate_.incrementArgumentCounter();

        Argument storage argument_ = debate_.arguments[newArgumentId];

        // Create a child node and add it to the mapping
        (argument_.pro, argument_.con) = DEBATE_DEPOSIT.split(
            100 - _initialApproval,
            _initialApproval
        );
        argument_.const = argument_.pro * argument_.con;
        argument_.vote = DEBATE_DEPOSIT;

        argument_.creator = msg.sender;
        argument_.finalizationTime = block.timestamp.toUint32() + phases[_debateId].timeUnit;
        argument_.parentArgumentId = _parentArgumentId;
        argument_.isSupporting = _isSupporting;
        argument_.state = State.Created;

        argument_.contentURI = _contentURI;
    }

    /// @notice Internal function to update a parent argument after the removal of a child argument in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _parentArgumentId The ID of the parent argument.
    function _updateParentAfterChildRemoval(uint256 _debateId, uint16 _parentArgumentId) internal {
        Debate storage debate_ = debates[_debateId];
        Argument storage parentArgument_ = debate_.arguments[_parentArgumentId];

        if (parentArgument_.state != State.Final) {
            revert StateInvalid({expected: State.Final, actual: parentArgument_.state});
        }

        parentArgument_.untalliedChilds--;

        // Eventually, the parent argument becomes a leaf after the removal
        if (parentArgument_.untalliedChilds == 0) {
            // append
            debate_.leafArgumentIds.push(_parentArgumentId);
        }
    }

    /// @notice Internal function to create a dispute for an argument in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to be disputed.
    /// @return disputeId The ID of the dispute created.
    function _createDispute(
        uint256 _debateId,
        uint16 _argumentId
    ) internal returns (uint256 disputeId) {
        (address recipient, ERC20 feeToken, uint256 feeAmount) = arbitrator.getDisputeFees();

        feeToken.safeTransferFrom(msg.sender, address(this), feeAmount);
        feeToken.safeApprove(recipient, feeAmount);
        disputeId = arbitrator.createDispute(
            2,
            abi.encodePacked(address(this), _debateId, _argumentId)
        ); // TODO 2 rulings?
        feeToken.safeApprove(recipient, 0); // reset just in case non-compliant tokens (that fail on non-zero to non-zero approvals) are used
    }

    /// @notice Internal function to submit evidence for a dispute for an argument in a debate.
    /// @param _disputeId The ID of the dispute to submit the evidence for.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    /// @param _contentURI The URI pointing to the argument content.
    /// @param _reason The reason for raising the dispute.
    function _submitEvidence(
        uint256 _debateId,
        uint16 _argumentId,
        uint256 _disputeId,
        bytes32 _contentURI,
        bytes calldata _reason
    ) internal {
        arbitrator.submitEvidence(
            _disputeId,
            msg.sender,
            abi.encode(_debateId, _argumentId, _contentURI)
        );
        arbitrator.submitEvidence(_disputeId, msg.sender, _reason);
        arbitrator.closeEvidencePeriod(_disputeId);
    }

    /// @notice Internal function to submit evidence for a dispute for an argument in a debate.
    /// @param _disputeId The ID of the dispute to submit the evidence for.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    function _addDispute(uint256 _debateId, uint16 _argumentId, uint256 _disputeId) internal {
        Debate storage debate_ = debates[_debateId];

        debate_.arguments[_argumentId].state = State.Disputed;
        debate_.disputedArgumentIds.push(_argumentId);

        disputes[_debateId][_argumentId] = _disputeId;
    }

    /// @notice Internal function to execute an investment to obtain pro tokens on the argument's market in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    /// @param _investment The container containing the investment data.
    function _executeProInvestment(
        uint256 _debateId,
        uint16 _argumentId,
        InvestmentData memory _investment
    ) internal {
        uint32 votes = _investment.voteTokensInvested - _investment.fee;

        Debate storage debate_ = debates[_debateId];
        Argument storage argument_ = debate_.arguments[_argumentId];

        debate_.totalVotes += votes;
        debate_.arguments[argument_.parentArgumentId].childsVote += votes;

        argument_.vote += votes;
        argument_.fees += _investment.fee;
        argument_.pro -= _investment.proSwap;
        argument_.con += _investment.conMint;
    }

    /// @notice Internal function to execute an investment to obtain cont tokens on the argument's market in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument to dispute.
    /// @param _investment The container containing the investment data.
    function _executeConInvestment(
        uint256 _debateId,
        uint16 _argumentId,
        InvestmentData memory _investment
    ) internal {
        uint32 votes = _investment.voteTokensInvested - _investment.fee;

        Debate storage debate_ = debates[_debateId];
        Argument storage argument_ = debate_.arguments[_argumentId];

        debate_.totalVotes += votes;
        debate_.arguments[argument_.parentArgumentId].childsVote += votes;

        argument_.vote += votes;
        argument_.fees += _investment.fee;
        argument_.pro += _investment.proMint;
        argument_.con -= _investment.conSwap;
    }

    /// @notice Internal function to calculate the amount of pro tokens obtained from swapping the minted con tokens.
    /// @param _proMint The amount of pro tokens.
    /// @param _conMint The amount of con tokens.
    /// @return proSwap The amount of pro tokens obtained from swapping the minted con tokens.
    function _calculateProSwap(
        uint32 _proMint,
        uint32 _conMint
    ) internal pure returns (uint32 proSwap) {
        return _proMint - _proMint / 2; // TODO Revisit formulas
    }

    /// @notice Internal function to calculate the amount of con tokens obtained from swapping the minted pro tokens.
    /// @param _proMint The amount of pro tokens.
    /// @param _conMint The amount of con tokens.
    /// @return conSwap The amount of con tokens obtained from swapping the minted pro tokens.
    function _calculateConSwap(
        uint32 _proMint,
        uint32 _conMint
    ) internal pure returns (uint32 conSwap) {
        conSwap = _proMint - _proMint / (1 + _proMint / _conMint); // TODO Revisit formulas
    }

    //function _calculateSwap(uint32 _proMint, uint32 _conMint, uint32 _swap) internal pure returns //(uint32) {
    //    return _proMint - _proMint / (1 + _swap / _conMint); // TODO Parentheses correct?
    //    // TODO is this really always the order? Does this stem from the pair?
    //}

    /// @notice Internal function to tally an argument in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument.
    function _tallyNode(uint256 _debateId, uint16 _argumentId) internal {
        Argument storage argument_ = debates[_debateId].arguments[_argumentId];
        uint16 parentArgumentId = argument_.parentArgumentId;
        Argument storage parentArgument_ = debates[_debateId].arguments[parentArgumentId];

        if (argument_.untalliedChilds > 0) {
            revert ChildsUntallied({untalliedChilds: argument_.untalliedChilds});
        }

        // Calculate own impact $r_j$
        int64 ownImpact = _calculateImpact(_debateId, _argumentId);

        // Apply pre-factor $\sigma_j$
        if (!argument_.isSupporting) {
            ownImpact = -ownImpact;
        }

        // Apply weight $w_j$
        uint32 ownVotes = argument_.vote;
        uint32 ownAndSibilingVotes = parentArgument_.childsVote; // This works, because the parent contains the votes of all children (the siblings).

        ownImpact = ownImpact.multipyByFraction(
            int64(uint64(ownVotes)),
            int64(uint64(ownAndSibilingVotes))
        );

        // Update the parent argument impact
        parentArgument_.childsImpact += ownImpact;
        parentArgument_.untalliedChilds--;

        // if all childs of the parent are tallied, tally parent
        if (parentArgument_.untalliedChilds == 0) {
            _tallyNode(_debateId, parentArgumentId);
        }

        emit ArgumentImpactCalculated({
            debateId: _debateId,
            argumentId: _argumentId,
            impact: ownImpact
        });
    }

    /// @notice Internal function to calculate the impact of an argument in a debate.
    /// @param _debateId The ID of the debate.
    /// @param _argumentId The ID of the argument.
    /// @return impact The impact of the argument.
    function _calculateImpact(
        uint256 _debateId,
        uint16 _argumentId
    ) internal view returns (int64 impact) {
        Argument storage argument_ = debates[_debateId].arguments[_argumentId];

        uint32 pro = argument_.pro;
        uint32 con = argument_.con;

        // calculate own impact
        impact = int64(uint64(type(uint32).max.multipyByFraction(pro, pro + con)));

        impact =
            impact.multipyByFraction(MIX_MAX - MIX_VAL, MIX_MAX) +
            (argument_.childsImpact).multipyByFraction(MIX_VAL, MIX_MAX);
    }
}
