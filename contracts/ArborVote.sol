//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./utils/UtilsLib.sol";
import "./interfaces/IArbitrator.sol";
import "./interfaces/IArbitrable.sol";
import "./interfaces/IProofOfHumanity.sol";

contract ArborVote is IArbitrable {
    using UtilsLib for uint16[];
    using UtilsLib for uint32;
    using UtilsLib for uint64;
    using UtilsLib for int64;
    using SafeERC20 for ERC20;

    enum State {
        Unitialized,
        Created,
        Final,
        Disputed,
        Invalid
    }

    struct Market {
        uint32 pro;
        uint32 con;
        uint32 const;
        uint32 vote;
        uint32 fees;
        int64 childsImpact;
    }

    struct Metadata {
        address creator; // 20 bytes
        uint32 finalizationTime; // 4 bytes
        uint16 parentId; // 2 bytes
        uint16 untalliedChilds; // 2 bytes
        bool isSupporting; // 1 byte
        State state; // 1 byte
    } // 30 bytes

    struct Argument {
        Metadata metadata; // 32 bytes
        bytes32 digest; // 32 bytes // TODO emit text only as event
        Market market; // 32 Bytes
    } // 3x 32 bytes

    struct Debate {
        uint16 argumentsCount;
        mapping(uint16 => Argument) arguments;
        uint16[] leafArgumentIds;
        uint16[] disputedArgumentIds;
    }

    struct InvestmentData {
        uint32 voteTokensInvested;
        uint32 proMint;
        uint32 conMint;
        uint32 fee;
        uint32 proSwap;
        uint32 conSwap;
    }

    enum Role {
        Unassigned,
        Participant,
        Juror
    }

    struct User {
        Role role;
        uint32 tokens;
        mapping(uint16 => Shares) shares;
    }

    struct Shares {
        uint32 pro;
        uint32 con;
    }

    enum Phase {
        Unitialized,
        Editing,
        Voting,
        Finished
    }

    struct PhaseData {
        Phase currentPhase; // 1 byte
        uint32 editingEndTime; // 4 bytes
        uint32 votingEndTime; // 4 bytes
        uint32 timeUnit; // 4 bytes
    }

    uint16 internal constant MAX_ARGUMENTS = type(uint16).max;

    uint32 internal constant DEBATE_DEPOSIT = 10;
    uint32 internal constant FEE_PERCENTAGE = 5;
    uint32 internal constant INITIAL_TOKENS = 100;

    int64 internal constant MIXING = 0x800000; // type(int64).max / 2 // TODO why negative?

    IProofOfHumanity private poh; // PoH mainnet: 0x1dAD862095d40d43c2109370121cf087632874dB

    uint32 public totalVotes;
    uint240 public debatesCount;
    mapping(uint240 => Debate) public debates;
    mapping(uint240 => mapping(uint16 => uint256)) public disputes;
    mapping(uint256 => mapping(address => User)) public users;
    mapping(uint256 => PhaseData) public phases;

    IArbitrator arbitrator;

    event Challenged(uint256 disputeId, uint240 debateId, uint16 argumentId, bytes reason);

    event Resolved(uint256 disputeId, uint240 debateId, uint16 argumentId);

    event Invested(
        address indexed buyer,
        uint240 indexed debateId,
        uint16 indexed argumentId,
        InvestmentData data
    );

    error WrongPhase(Phase expected, Phase actual);
    error WrongState(State expected, State actual);
    error WrongRole(Role expected, Role actual);
    error WrongAddress(address expected, address actual);

    modifier onlyPhase(uint256 _debateId, Phase _phase) {
        _onlyPhase(_debateId, _phase);
        _;
    }

    function _onlyPhase(uint256 _debateId, Phase _phase) internal view {
        if (phases[_debateId].currentPhase != _phase)
            revert WrongPhase({expected: _phase, actual: phases[_debateId].currentPhase});
    }

    modifier excludePhase(uint256 _debateId, Phase _phase) {
        _excludePhase(_debateId, _phase);
        _;
    }

    function _excludePhase(uint256 _debateId, Phase _phase) internal view {
        if (phases[_debateId].currentPhase == _phase) {
            revert WrongPhase({expected: _phase, actual: phases[_debateId].currentPhase});
        }
    }

    modifier onlyArgumentState(
        uint240 _debateId,
        uint16 _argumentId,
        State _state
    ) {
        _onlyArgumentState(_debateId, _argumentId, _state);
        _;
    }

    function _onlyArgumentState(uint240 _debateId, uint16 _argumentId, State _state) internal view {
        State state = debates[_debateId].arguments[_argumentId].metadata.state;
        if (state != _state) {
            revert WrongState({expected: _state, actual: state});
        }
    }

    modifier onlyCreator(uint240 _debateId, uint16 _argumentId) {
        _onlyCreator(_debateId, _argumentId);
        _;
    }

    function _onlyCreator(uint240 _debateId, uint16 _argumentId) internal view {
        address creator = debates[_debateId].arguments[_argumentId].metadata.creator;
        if (msg.sender != creator) {
            revert WrongAddress({expected: creator, actual: msg.sender});
        }
    }

    modifier onlyRole(uint256 _debateId, Role _role) {
        _onlyRole(_debateId, _role);
        _;
    }

    function _onlyRole(uint256 _debateId, Role _role) internal view {
        Role role = users[_debateId][msg.sender].role;
        if (role != _role) {
            revert WrongRole({expected: _role, actual: role});
        }
    }

    function initialize(IProofOfHumanity _poh) external {
        poh = _poh;
    }

    function createDebate(
        bytes32 _ipfsHash,
        uint32 _timeUnit
    ) external onlyArgumentState(debatesCount, 0, State.Unitialized) returns (uint240 debateId) {
        // Create the root Argument

        Debate storage currentDebate_ = debates[debatesCount];
        Argument storage rootArgument_ = currentDebate_.arguments[0];

        // Create the root argument of the tree
        rootArgument_.metadata.creator = msg.sender;
        rootArgument_.metadata.finalizationTime = uint32(block.timestamp);
        rootArgument_.metadata.isSupporting = true;
        rootArgument_.metadata.state = State.Final;
        rootArgument_.digest = _ipfsHash;

        debateId = debatesCount; // TODO use OZ counter

        // Store the phase related data
        PhaseData storage phaseData_ = phases[debateId];
        phaseData_.currentPhase = Phase.Editing;
        phaseData_.timeUnit = _timeUnit;
        phaseData_.editingEndTime = uint32(block.timestamp + 7 * _timeUnit);
        phaseData_.votingEndTime = uint32(block.timestamp + 10 * _timeUnit);

        // increment counters
        currentDebate_.argumentsCount++;
        unchecked {
            ++debatesCount;
        }
    }

    function updatePhase(uint240 _debateId) public {
        uint32 currentTime = uint32(block.timestamp);

        PhaseData storage phaseData_ = phases[_debateId];

        if (currentTime > phaseData_.votingEndTime && phaseData_.currentPhase != Phase.Finished) {
            phaseData_.currentPhase = Phase.Finished;
        } else if (
            currentTime > phaseData_.editingEndTime && phaseData_.currentPhase != Phase.Voting
        ) {
            phaseData_.currentPhase = Phase.Voting;
        }
    }

    function join(
        uint240 _debateId
    ) external excludePhase(_debateId, Phase.Finished) onlyRole(_debateId, Role.Unassigned) {
        require(poh.isRegistered(msg.sender)); // not failsafe - takes 3.5 days to switch address
        _initializeParticipant(_debateId, msg.sender);
    }

    function debateResult(uint240 _debateId) external view returns (bool) {
        if (phases[_debateId].currentPhase != Phase.Finished)
            revert WrongPhase({expected: Phase.Finished, actual: phases[_debateId].currentPhase});

        return debates[_debateId].arguments[0].market.childsImpact > 0;
    }

    function _initializeParticipant(uint240 _debateId, address _user) internal {
        User storage user_ = users[_debateId][_user];

        user_.role = Role.Participant;
        user_.tokens = INITIAL_TOKENS;
    }

    function finalizeArgument(
        uint240 _debateId,
        uint16 _argumentId
    ) public onlyArgumentState(_debateId, _argumentId, State.Created) {
        Metadata storage metadata_ = debates[_debateId].arguments[_argumentId].metadata;

        require(metadata_.finalizationTime <= uint32(block.timestamp)); // TODO emit error

        metadata_.state = State.Final;
    }

    /*
     * @notice Create an argument with an initial approval
     */
    function addArgument(
        uint240 _debateId,
        uint16 _parentArgumentId,
        bytes32 _ipfsHash,
        bool _isSupporting,
        uint32 _initialApproval
    )
        public
        onlyRole(_debateId, Role.Participant)
        onlyArgumentState(_debateId, _parentArgumentId, State.Final)
    {
        User storage user_ = users[_debateId][msg.sender];

        require(50 <= _initialApproval && _initialApproval <= 100);
        require(user_.tokens >= DEBATE_DEPOSIT);

        // initialize market
        Debate storage debate_ = debates[_debateId];

        user_.tokens -= DEBATE_DEPOSIT;

        // Create new argument
        uint16 newArgumentId = _createArgument(
            _debateId,
            _parentArgumentId,
            _ipfsHash,
            _isSupporting,
            _initialApproval
        );

        // Update parent
        debate_.arguments[_parentArgumentId].metadata.untalliedChilds++;

        // Update the debate's leaf arguments if this is not the root argument
        if (_parentArgumentId != 0) {
            debate_.leafArgumentIds.removeById(_parentArgumentId);
        }
        debate_.leafArgumentIds.push(newArgumentId);
    }

    function _createArgument(
        uint240 _debateId,
        uint16 _parentArgumentId,
        bytes32 _ipfsHash,
        bool _isSupporting,
        uint32 _initialApproval
    ) internal returns (uint16 newArgumentId) {
        Debate storage debate_ = debates[_debateId];

        newArgumentId = debate_.argumentsCount; // TODO use counter
        debate_.argumentsCount++;

        Argument storage argument_ = debate_.arguments[newArgumentId];

        // Create a child node and add it to the mapping
        (argument_.market.pro, argument_.market.con) = DEBATE_DEPOSIT.split(
            100 - _initialApproval,
            _initialApproval
        );
        argument_.market.const = argument_.market.pro * argument_.market.con; // TODO local variable?
        argument_.market.vote = DEBATE_DEPOSIT;

        argument_.metadata.creator = msg.sender;
        argument_.metadata.finalizationTime = uint32(block.timestamp) + phases[_debateId].timeUnit;
        argument_.metadata.parentId = _parentArgumentId;
        argument_.metadata.isSupporting = _isSupporting;
        argument_.metadata.state = State.Created;

        argument_.digest = _ipfsHash;
    }

    function moveArgument(
        uint240 _debateId,
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
        uint16 oldParentArgumentId = movedArgument_.metadata.parentId;
        _updateParentAfterChildRemoval(_debateId, oldParentArgumentId);

        // change argument state
        movedArgument_.metadata.parentId = _newParentArgumentId;

        // change new parent argument state
        debate_.arguments[_newParentArgumentId].metadata.untalliedChilds++;
    }

    function _updateParentAfterChildRemoval(uint240 _debateId, uint16 _parentArgumentId) internal {
        Debate storage debate_ = debates[_debateId];
        Argument storage parentArgument_ = debate_.arguments[_parentArgumentId];

        require(parentArgument_.metadata.state == State.Final);

        parentArgument_.metadata.untalliedChilds--;

        // Eventually, the parent argument becomes a leaf after the removal
        if (parentArgument_.metadata.untalliedChilds == 0) {
            // append
            debate_.leafArgumentIds.push(_parentArgumentId);
        }
    }

    function alterArgument(
        uint240 _debateId,
        uint16 _argumentId,
        bytes32 _ipfsHash
    )
        external
        onlyPhase(_debateId, Phase.Editing)
        onlyCreator(_debateId, _argumentId)
        onlyArgumentState(_debateId, _argumentId, State.Created)
    {
        uint32 newFinalizationTime = uint32(block.timestamp) + phases[_debateId].timeUnit;

        require(newFinalizationTime <= phases[_debateId].editingEndTime);

        Argument storage alteredArgument_ = debates[_debateId].arguments[_argumentId];
        alteredArgument_.metadata.finalizationTime = newFinalizationTime;
        alteredArgument_.digest = _ipfsHash;

        // TODO
    }

    function _createDispute(
        uint240 _debateId,
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

    function _submitEvidence(
        uint256 _disputeId,
        uint240 _debateId,
        uint16 _argumentId,
        bytes32 _digest,
        bytes calldata _reason
    ) internal {
        arbitrator.submitEvidence(
            _disputeId,
            msg.sender,
            abi.encode(_debateId, _argumentId, _digest)
        );
        arbitrator.submitEvidence(_disputeId, msg.sender, _reason);
        arbitrator.closeEvidencePeriod(_disputeId);
    }

    function challenge(
        uint240 _debateId,
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
            disputeId,
            _debateId,
            _argumentId,
            debates[_debateId].arguments[_argumentId].digest,
            _reason
        );

        // state changes
        _addDispute(_debateId, _argumentId, disputeId);

        emit Challenged({
            disputeId: disputeId,
            debateId: _debateId,
            argumentId: _argumentId,
            reason: _reason
        });
    }

    function resolve(
        uint240 _debateId,
        uint16 _argumentId
    )
        external
        onlyPhase(_debateId, Phase.Editing)
        onlyArgumentState(_debateId, _argumentId, State.Disputed)
    {
        uint256 disputeId = disputes[_debateId][_argumentId];

        // fetch ruling
        (address subject, uint256 ruling) = arbitrator.rule(disputeId);
        require(subject == address(this));

        if (ruling == 0) {
            _clearDispute(_debateId, _argumentId, State.Final);
        } else {
            _clearDispute(_debateId, _argumentId, State.Invalid);
        }

        emit Ruled({arbitrator: arbitrator, disputeId: disputeId, ruling: ruling});
        emit Resolved({disputeId: disputeId, debateId: _debateId, argumentId: _argumentId});
    }

    function calculateMint(
        uint240 _debateId,
        uint16 _argumentId,
        uint32 _voteTokenAmount
    ) public view returns (InvestmentData memory data) {
        data.voteTokensInvested = _voteTokenAmount;

        Argument storage argument_ = debates[_debateId].arguments[_argumentId];

        data.fee = _voteTokenAmount.multipyByFraction(FEE_PERCENTAGE, 100);
        (uint32 proMint, uint32 conMint) = (_voteTokenAmount - data.fee).split(
            argument_.market.pro,
            argument_.market.con
        );

        data.proMint = proMint;
        data.conMint = conMint;

        data.proSwap = _calculateSwap(proMint, conMint, conMint);
        data.conSwap = _calculateSwap(proMint, conMint, proMint);
    }

    function investInPro(
        uint240 _debateId,
        uint16 _argumentId,
        uint32 _amount
    ) external onlyPhase(_debateId, Phase.Voting) {
        User storage user_ = users[_debateId][msg.sender];

        require(user_.tokens >= _amount);
        user_.tokens -= _amount;

        InvestmentData memory data = calculateMint(_debateId, _argumentId, _amount);
        _executeProInvestment(_debateId, _argumentId, data);

        data.conSwap = 0;

        user_.shares[_argumentId].pro += _amount;

        emit Invested({
            buyer: msg.sender,
            debateId: _debateId,
            argumentId: _argumentId,
            data: data
        });
    }

    function investInCon(
        uint240 _debateId,
        uint16 _argumentId,
        uint32 _amount
    ) external onlyPhase(_debateId, Phase.Voting) {
        User storage user_ = users[_debateId][msg.sender];

        require(user_.tokens >= _amount);
        user_.tokens -= _amount;

        InvestmentData memory data = calculateMint(_debateId, _argumentId, _amount);
        _executeConInvestment(_debateId, _argumentId, data);

        data.proSwap = 0;

        user_.shares[_argumentId].con += _amount;

        emit Invested({
            buyer: msg.sender,
            debateId: _debateId,
            argumentId: _argumentId,
            data: data
        });
    }

    function tallyTree(uint240 _debateId) external onlyPhase(_debateId, Phase.Finished) {
        require(debates[_debateId].disputedArgumentIds.length == 0); // TODO: because things are finished, we can assume this is zero

        uint16[] memory leafArgumentIds = debates[_debateId].leafArgumentIds;

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _tallyNode(_debateId, leafArgumentIds[i]);
        }

        phases[_debateId].currentPhase = Phase.Finished;
    }

    function _executeProInvestment(
        uint240 _debateId,
        uint16 _argumentId,
        InvestmentData memory data
    ) internal {
        uint32 votes = data.voteTokensInvested - data.fee;
        totalVotes += votes;

        Market storage market_ = debates[_debateId].arguments[_argumentId].market;

        market_.vote += votes;
        market_.fees += data.fee;
        market_.con += data.conMint;
        market_.pro -= data.proSwap;
    }

    function _executeConInvestment(
        uint240 _debateId,
        uint16 _argumentId,
        InvestmentData memory data
    ) internal {
        uint32 votes = data.voteTokensInvested - data.fee;
        totalVotes += votes;

        Market storage market_ = debates[_debateId].arguments[_argumentId].market;

        market_.vote += votes;
        market_.fees += data.fee;
        market_.pro += data.proMint;
        market_.con -= data.conSwap;
    }

    function _addDispute(uint240 _debateId, uint16 _argumentId, uint256 _disputeId) internal {
        Debate storage debate_ = debates[_debateId];

        debate_.arguments[_argumentId].metadata.state = State.Disputed;
        debate_.disputedArgumentIds.push(_argumentId);

        disputes[_debateId][_argumentId] = _disputeId;
    }

    function _clearDispute(uint240 _debateId, uint16 _argumentId, State _state) internal {
        Debate storage debate_ = debates[_debateId];

        debate_.arguments[_argumentId].metadata.state = _state;
        debate_.disputedArgumentIds.removeById(_argumentId);
    }

    // TODO add explanation
    function _calculateSwap(uint32 _pro, uint32 _con, uint32 _swap) internal pure returns (uint32) {
        return _pro - _pro / (1 + _swap / _con);
        // TODO is this really always the order? Does this stem from the pair?
    }

    function _calculateOwnImpact(
        uint240 _debateId,
        uint16 _argumentId
    ) internal view returns (int64 own) {
        Argument storage argument_ = debates[_debateId].arguments[_argumentId];

        uint32 pro = argument_.market.pro;
        uint32 con = argument_.market.con;

        // calculate own impact
        own = int64(uint64(type(uint32).max.multipyByFraction(pro, pro + con)));

        own =
            own.multipyByFraction(type(int64).max - int64(MIXING), type(int64).max) +
            (argument_.market.childsImpact).multipyByFraction(int64(MIXING), type(int64).max);

        if (argument_.metadata.isSupporting) {
            own = -own;
        }
    }

    function _tallyNode(uint240 _debateId, uint16 _argumentId) internal {
        Argument storage argument_ = debates[_debateId].arguments[_argumentId];
        uint16 parentArgumentId = argument_.metadata.parentId;
        Argument storage parentArgument_ = debates[_debateId].arguments[parentArgumentId];

        require(argument_.metadata.untalliedChilds == 0); // All childs must be tallied first

        int64 own = _calculateOwnImpact(_debateId, _argumentId);

        // TODO weight calculation

        parentArgument_.market.childsImpact += own;
        parentArgument_.metadata.untalliedChilds--;

        // if all childs of the parent are tallied, tally parent
        if (argument_.metadata.untalliedChilds == 0) {
            _tallyNode(_debateId, parentArgumentId);
        }
    }
}
