//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./utils/UtilsLib.sol";
import "./interfaces/IArbitrator.sol";
import "./interfaces/IArbitrable.sol";
import "./interfaces/IProofOfHumanity.sol";

library DebateLib {
    // https://docs.ipfs.io/concepts/content-addressing/
    // https://richardschneider.github.io/net-ipfs-core/articles/multihash.html

    uint16 internal constant MAX_ARGUMENTS = type(uint16).max;

    // TODO make parameters
    int64 internal constant MIXING = 0x800000; // type(int64).max / 2

    uint32 internal constant DEBATE_DEPOSIT = 10;
    uint32 internal constant FEE_PERCENTAGE = 5;

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

    struct Identifier {
        uint240 debate;
        uint16 argument;
    }

    struct Metadata {
        address creator; // 20 bytes
        uint32 finalizationTime; // 4 bytes
        uint16 parentId; // 2 bytes
        uint16 untalliedChilds; // 2 bytes
        bool isSupporting; // 1 byte
        State state; // 1 byte
    }

    struct Argument {
        Metadata metadata; // 32 bytes
        bytes32 digest; // 32 bytes
        Market market; // 32 Bytes
    } // 3x 32 bytes

    /*     struct Multihash {
        bytes32 digest;
        uint8 hashFunction;
        uint8 size;
    }

    function getMultihash(Argument storage _argument) public view returns (Multihash memory) {
        return Multihash(_argument.digest, IPFS_HASH_FUNCTION, IPFS_HASH_SIZE);
    } */

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
}

library UserLib {
    uint16 internal constant MAX_ARGUMENTS = 2**16 - 1;
    uint32 internal constant INITIAL_TOKENS = 100;

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
}

library PhaseLib {
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
}

contract ArborVote is IArbitrable {
    using UtilsLib for uint16[];
    using UtilsLib for uint32;
    using UtilsLib for uint64;
    using UtilsLib for int64;
    using SafeERC20 for ERC20;

    IProofOfHumanity private pohProxy; // PoH mainnet: 0x1dAD862095d40d43c2109370121cf087632874dB

    uint16 constant MAX_ARGUMENTS = 2**16 - 1;
    uint32 constant INITIAL_TOKENS = 100;

    uint32 public totalVotes;
    uint240 public debatesCount;
    mapping(uint240 => DebateLib.Debate) public debates;
    mapping(uint240 => mapping(uint16 => uint256)) public disputes;
    mapping(uint256 => mapping(address => UserLib.User)) public users;
    mapping(uint256 => PhaseLib.PhaseData) public phases;

    IArbitrator arbitrator;

    event Challenged(uint256 disputeId, DebateLib.Identifier id, bytes reason);

    event Resolved(uint256 disputeId, DebateLib.Identifier id);

    event Invested(
        address indexed buyer,
        DebateLib.Identifier indexed _arg,
        DebateLib.InvestmentData indexed data
    );

    error WrongPhase(PhaseLib.Phase expected, PhaseLib.Phase actual);
    error WrongState(DebateLib.State expected, DebateLib.State actual);
    error WrongRole(UserLib.Role expected, UserLib.Role actual);
    error WrongAddress(address expected, address actual);

    function initialize() external {}

    modifier onlyPhase(uint256 _debateId, PhaseLib.Phase _phase) {
        _onlyPhase(_debateId, _phase);
        _;
    }

    function _onlyPhase(uint256 _debateId, PhaseLib.Phase _phase) internal view {
        if (phases[_debateId].currentPhase != _phase)
            revert WrongPhase({expected: _phase, actual: phases[_debateId].currentPhase});
    }

    modifier excludePhase(uint256 _debateId, PhaseLib.Phase _phase) {
        _excludePhase(_debateId, _phase);
        _;
    }

    function _excludePhase(uint256 _debateId, PhaseLib.Phase _phase) internal view {
        if (phases[_debateId].currentPhase == _phase)
            revert WrongPhase({expected: _phase, actual: phases[_debateId].currentPhase});
    }

    modifier onlyArgumentState(DebateLib.Identifier memory _arg, DebateLib.State _state) {
        _onlyArgumentState(_arg, _state);
        _;
    }

    function _onlyArgumentState(DebateLib.Identifier memory _arg, DebateLib.State _state)
        internal
        view
    {
        if (debates[_arg.debate].arguments[_arg.argument].metadata.state != _state)
            revert WrongState({
                expected: _state,
                actual: debates[_arg.debate].arguments[_arg.argument].metadata.state
            });
    }

    modifier onlyCreator(DebateLib.Identifier memory _arg) {
        _onlyCreator(_arg);
        _;
    }

    function _onlyCreator(DebateLib.Identifier memory _arg) internal view {
        if (msg.sender != debates[_arg.debate].arguments[_arg.argument].metadata.creator)
            revert WrongAddress({
                expected: debates[_arg.debate].arguments[_arg.argument].metadata.creator,
                actual: msg.sender
            });
    }

    modifier onlyRole(uint256 _debateId, UserLib.Role _role) {
        _onlyRole(_debateId, _role);
        _;
    }

    function _onlyRole(uint256 _debateId, UserLib.Role _role) internal view {
        if (users[_debateId][msg.sender].role != _role)
            revert WrongRole({expected: _role, actual: users[_debateId][msg.sender].role});
    }

    function createDebate(bytes32 _ipfsHash, uint32 _timeUnit)
        external
        onlyArgumentState(
            DebateLib.Identifier({debate: debatesCount, argument: 0}),
            DebateLib.State.Unitialized
        )
        returns (uint240 debateId)
    {
        DebateLib.Argument memory rootArgument = DebateLib.Argument({
            metadata: DebateLib.Metadata({
                creator: msg.sender,
                finalizationTime: uint32(block.timestamp),
                parentId: 0,
                untalliedChilds: 0,
                isSupporting: true,
                state: DebateLib.State.Final
            }),
            digest: _ipfsHash,
            market: DebateLib.Market({pro: 0, con: 0, const: 0, vote: 0, fees: 0, childsImpact: 0})
        });

        debateId = debatesCount;

        _initializePhases(debateId, _timeUnit);
        _initializeDebate(rootArgument);
    }

    function updatePhase(uint240 _debateId) public {
        uint32 currentTime = uint32(block.timestamp);

        if (
            currentTime > phases[_debateId].votingEndTime &&
            phases[_debateId].currentPhase != PhaseLib.Phase.Finished
        ) {
            phases[_debateId].currentPhase = PhaseLib.Phase.Finished;
        } else if (
            currentTime > phases[_debateId].editingEndTime &&
            phases[_debateId].currentPhase != PhaseLib.Phase.Voting
        ) {
            phases[_debateId].currentPhase = PhaseLib.Phase.Voting;
        }
    }

    function join(uint240 _debateId)
        external
        excludePhase(_debateId, PhaseLib.Phase.Finished)
        onlyRole(_debateId, UserLib.Role.Unassigned)
    {
        require(pohProxy.isRegistered(msg.sender)); // not failsafe - takes 3.5 days to switch address
        _initializeParticipant(_debateId, msg.sender);
    }

    function debateResult(uint240 _debateId) external view returns (bool) {
        if (phases[_debateId].currentPhase != PhaseLib.Phase.Finished)
            revert WrongPhase({
                expected: PhaseLib.Phase.Finished,
                actual: phases[_debateId].currentPhase
            });

        return debates[_debateId].arguments[0].market.childsImpact > 0;
    }

    function _initializeParticipant(uint240 _debateId, address _user) internal {
        users[_debateId][_user].role = UserLib.Role.Participant;
        users[_debateId][_user].tokens = UserLib.INITIAL_TOKENS;
    }

    function _initializeDebate(DebateLib.Argument memory rootArgument) internal {
        debates[debatesCount].arguments[0] = rootArgument;
        // increment counters
        debates[debatesCount].argumentsCount++;
        debatesCount++;
    }

    function addProTokens(
        DebateLib.Identifier memory _arg,
        address _user,
        uint32 _amount
    ) internal {
        users[_arg.debate][_user].shares[_arg.argument].pro += _amount;
    }

    function addConTokens(
        DebateLib.Identifier memory _arg,
        address _user,
        uint32 _amount
    ) internal {
        users[_arg.debate][_user].shares[_arg.argument].con += _amount;
    }

    function finalizeArgument(DebateLib.Identifier memory _arg)
        public
        onlyArgumentState(_arg, DebateLib.State.Created)
    {
        require(
            debates[_arg.debate].arguments[_arg.argument].metadata.finalizationTime <=
                uint32(block.timestamp)
        );

        debates[_arg.debate].arguments[_arg.argument].metadata.state = DebateLib.State.Final;
    }

    /*
     * @notice Create an argument with an initial approval
     */
    function addArgument(
        DebateLib.Identifier memory _parent,
        bytes32 _ipfsHash,
        bool _isSupporting,
        uint32 _initialApproval
    )
        public
        onlyRole(_parent.debate, UserLib.Role.Participant)
        onlyArgumentState(_parent, DebateLib.State.Final)
    {
        require(50 <= _initialApproval && _initialApproval <= 100);
        require(users[_parent.debate][msg.sender].tokens >= DebateLib.DEBATE_DEPOSIT);

        // initialize market
        DebateLib.Market memory market;
        {
            // Create a child node and add it to the mapping
            users[_parent.debate][msg.sender].tokens -= DebateLib.DEBATE_DEPOSIT;
            (uint32 pro, uint32 con) = DebateLib.DEBATE_DEPOSIT.split(
                100 - _initialApproval,
                _initialApproval
            );
            market = DebateLib.Market({
                pro: pro,
                con: con,
                const: pro * con,
                vote: DebateLib.DEBATE_DEPOSIT,
                fees: 0,
                childsImpact: 0
            });
        }

        uint32 finalizationTime;
        {
            finalizationTime = uint32(block.timestamp) + phases[_parent.debate].timeUnit;
        }

        DebateLib.Metadata memory metadata = DebateLib.Metadata({
            creator: msg.sender,
            finalizationTime: finalizationTime,
            //ownId : argumentId,
            parentId: _parent.argument,
            untalliedChilds: 0,
            isSupporting: _isSupporting,
            state: DebateLib.State.Created
        });

        _addArgument(
            _parent.debate,
            DebateLib.Argument({metadata: metadata, digest: _ipfsHash, market: market})
        );
    }

    function moveArgument(DebateLib.Identifier memory _arg, uint16 _newParentArgumentId)
        external
        onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
        onlyCreator(_arg)
        onlyArgumentState(_arg, DebateLib.State.Created)
    {
        // change old parent state (which eventually becomes a leaf because of the removal)
        {
            DebateLib.Identifier memory oldParent = DebateLib.Identifier({
                debate: _arg.debate,
                argument: debates[_arg.debate].arguments[_arg.argument].metadata.parentId
            });

            require(
                debates[oldParent.debate].arguments[oldParent.argument].metadata.state ==
                    DebateLib.State.Final
            );

            debates[oldParent.debate].arguments[oldParent.argument].metadata.untalliedChilds--;

            if (
                debates[oldParent.debate].arguments[oldParent.argument].metadata.untalliedChilds ==
                0
            ) {
                // append
                debates[_arg.debate].leafArgumentIds.push(oldParent.argument);
            }
        }

        // change argument state
        debates[_arg.debate].arguments[_arg.argument].metadata.parentId = _newParentArgumentId;

        // change new parent state
        debates[_arg.debate].arguments[_newParentArgumentId].metadata.untalliedChilds++;
    }

    function alterArgument(DebateLib.Identifier memory _arg, bytes32 _ipfsHash)
        external
        onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
        onlyCreator(_arg)
        onlyArgumentState(_arg, DebateLib.State.Created)
    {
        uint32 newFinalizationTime = uint32(block.timestamp) + phases[_arg.debate].timeUnit;

        require(newFinalizationTime <= phases[_arg.debate].editingEndTime);

        debates[_arg.debate]
            .arguments[_arg.argument]
            .metadata
            .finalizationTime = newFinalizationTime;
        debates[_arg.debate].arguments[_arg.argument].digest = _ipfsHash;
    }

    function challenge(DebateLib.Identifier memory _arg, bytes calldata _reason)
        external
        onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
        onlyArgumentState(_arg, DebateLib.State.Final)
        returns (uint256 disputeId)
    {
        // create dispute
        {
            (address recipient, ERC20 feeToken, uint256 feeAmount) = arbitrator.getDisputeFees();

            feeToken.safeTransferFrom(msg.sender, address(this), feeAmount);
            feeToken.safeApprove(recipient, feeAmount);
            disputeId = arbitrator.createDispute(
                2,
                abi.encodePacked(address(this), _arg.debate, _arg.argument)
            ); // TODO 2 rulings?
            feeToken.safeApprove(recipient, 0); // reset just in case non-compliant tokens (that fail on non-zero to non-zero approvals) are used
        }

        // submit evidence
        {
            arbitrator.submitEvidence(
                disputeId,
                msg.sender,
                abi.encode(
                    _arg,
                    debates[_arg.debate].arguments[_arg.argument].digest
                    //,
                    //DebateLib.IPFS_HASH_FUNCTION,
                    //DebateLib.IPFS_HASH_SIZE
                )
            );
            arbitrator.submitEvidence(disputeId, msg.sender, _reason);
            arbitrator.closeEvidencePeriod(disputeId);
        }

        // state changes
        _addDispute(_arg, disputeId);

        emit Challenged(disputeId, _arg, _reason);
    }

    function resolve(DebateLib.Identifier memory _arg)
        external
        onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
        onlyArgumentState(_arg, DebateLib.State.Disputed)
    {
        uint256 disputeId = disputes[_arg.debate][_arg.argument];

        // fetch ruling
        (address subject, uint256 ruling) = arbitrator.rule(disputeId);
        require(subject == address(this));

        if (ruling == 0) {
            _clearDispute(_arg, DebateLib.State.Final);
        } else {
            _clearDispute(_arg, DebateLib.State.Invalid);
        }

        emit Ruled(arbitrator, disputeId, ruling);
        emit Resolved(disputeId, _arg);
    }

    function calculateMint(DebateLib.Identifier memory _arg, uint32 _voteTokenAmount)
        public
        view
        returns (DebateLib.InvestmentData memory data)
    {
        data.voteTokensInvested = _voteTokenAmount;

        data.fee = _voteTokenAmount.multipyByFraction(DebateLib.FEE_PERCENTAGE, 100);
        (uint32 proMint, uint32 conMint) = (_voteTokenAmount - data.fee).split(
            debates[_arg.debate].arguments[_arg.argument].market.pro,
            debates[_arg.debate].arguments[_arg.argument].market.con
        );

        data.proMint = proMint;
        data.conMint = conMint;

        data.proSwap = _calculateSwap(proMint, conMint, conMint);
        data.conSwap = _calculateSwap(proMint, conMint, proMint);
    }

    function investInPro(DebateLib.Identifier memory _arg, uint32 _amount)
        external
        onlyPhase(_arg.debate, PhaseLib.Phase.Voting)
    {
        require(users[_arg.debate][msg.sender].tokens >= _amount);
        users[_arg.debate][msg.sender].tokens -= _amount;

        DebateLib.InvestmentData memory data = calculateMint(_arg, _amount);
        _executeProInvestment(_arg, data);

        data.conSwap = 0;

        addProTokens(_arg, msg.sender, data.proMint + data.proSwap);

        emit Invested(msg.sender, _arg, data);
    }

    function investInCon(DebateLib.Identifier memory _arg, uint32 _amount)
        external
        onlyPhase(_arg.debate, PhaseLib.Phase.Voting)
    {
        require(users[_arg.debate][msg.sender].tokens >= _amount);
        users[_arg.debate][msg.sender].tokens -= _amount;

        DebateLib.InvestmentData memory data = calculateMint(_arg, _amount);
        _executeConInvestment(_arg, data);

        data.proSwap = 0;

        addConTokens(_arg, msg.sender, data.conMint + data.conSwap);

        emit Invested(msg.sender, _arg, data);
    }

    /*     function tallyTree(uint240 _debateId) external onlyPhase(_debateId, PhaseLib.Phase.Finished) {
        require(debates[_debateId].disputedArgumentIds.length == 0); // TODO: because things are finished, we can assume this is zero

        uint16[] memory leafArgumentIds = debates[_debateId].leafArgumentIds;

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _tallyNode(DebateLib.Identifier({debate: _debateId, argument: leafArgumentIds[i]}));
        }

        phases[_debateId].currentPhase = PhaseLib.Phase.Finished;
    } */

    function _initializePhases(uint256 _debateId, uint32 _timeUnit) internal {
        phases[_debateId].currentPhase = PhaseLib.Phase.Editing;
        phases[_debateId].timeUnit = _timeUnit;
        phases[_debateId].editingEndTime = uint32(block.timestamp + 7 * _timeUnit);
        phases[_debateId].votingEndTime = uint32(block.timestamp + 10 * _timeUnit);
    }

    function _executeProInvestment(
        DebateLib.Identifier memory _arg,
        DebateLib.InvestmentData memory data
    ) internal {
        uint32 votes = data.voteTokensInvested - data.fee;
        totalVotes += votes;
        
        debates[_arg.debate].arguments[_arg.argument].market.vote += votes;
        debates[_arg.debate].arguments[_arg.argument].market.fees += data.fee;
        debates[_arg.debate].arguments[_arg.argument].market.con += data.conMint;
        debates[_arg.debate].arguments[_arg.argument].market.pro -= data.proSwap;
    }

    function _executeConInvestment(
        DebateLib.Identifier memory _arg,
        DebateLib.InvestmentData memory data
    ) internal {
        uint32 votes = data.voteTokensInvested - data.fee;
        totalVotes += votes;
        debates[_arg.debate].arguments[_arg.argument].market.vote += votes;
        debates[_arg.debate].arguments[_arg.argument].market.fees += data.fee;
        debates[_arg.debate].arguments[_arg.argument].market.pro += data.proMint;
        debates[_arg.debate].arguments[_arg.argument].market.con -= data.conSwap;
    }

    function _addArgument(uint240 _debateId, DebateLib.Argument memory _argument) internal {
        debates[_debateId].arguments[debates[_debateId].argumentsCount] = _argument;
        if (_argument.metadata.parentId != 0) {
            debates[_debateId].leafArgumentIds.removeById(_argument.metadata.parentId);
        }
        debates[_debateId].arguments[_argument.metadata.parentId].metadata.untalliedChilds++;
        debates[_debateId].leafArgumentIds.push(debates[_debateId].argumentsCount);
        debates[_debateId].argumentsCount++;
    }

    function _addDispute(DebateLib.Identifier memory _arg, uint256 _disputeId) internal {
        debates[_arg.debate].arguments[_arg.argument].metadata.state = DebateLib.State.Disputed;
        debates[_arg.debate].disputedArgumentIds.push(_arg.argument);
        disputes[_arg.debate][_arg.argument] = _disputeId;
    }

    function _clearDispute(DebateLib.Identifier memory _arg, DebateLib.State _state) internal {
        debates[_arg.debate].arguments[_arg.argument].metadata.state = _state;
        debates[_arg.debate].disputedArgumentIds.removeById(_arg.argument);
    }

    // TODO add explanation
    function _calculateSwap(
        uint32 _pro,
        uint32 _con,
        uint32 _swap
    ) internal pure returns (uint32) {
        return _pro - _pro / (1 + _swap / _con);
        // TODO is this really always the order? Does this stem from the pair?
    }
    /* 
    function _calculateOwnImpact(DebateLib.Identifier memory _arg)
        internal
        view
        returns (int64 own)
    {
        uint32 pro = debates[_arg.debate].arguments[_arg.argument].market.pro;
        uint32 con = debates[_arg.debate].arguments[_arg.argument].market.con;

        // calculate own impact
        own = int64(uint64(type(uint32).max.multipyByFraction(pro, pro + con)));

        own =
            own.multipyByFraction(type(int64).max - int64(DebateLib.MIXING), type(int64).max) +
            (debates[_arg.debate].arguments[_arg.argument].market.childsImpact).multipyByFraction(
                int64(DebateLib.MIXING),
                type(int64).max
            );

        if (debates[_arg.debate].arguments[_arg.argument].metadata.isSupporting) own = -own;
    }

    function _tallyNode(DebateLib.Identifier memory _arg) internal {
        require(debates[_arg.debate].arguments[_arg.argument].metadata.untalliedChilds == 0); // All childs must be tallied first

        int64 own = _calculateOwnImpact(_arg);

        // Change parent state
        uint16 parentId = debates[_arg.debate].arguments[_arg.argument].metadata.parentId;
        // TODO weight calculation

        debates[_arg.debate].arguments[parentId].market.childsImpact += own;
        debates[_arg.debate].arguments[parentId].metadata.untalliedChilds--;

        // if all childs of the parent are tallied, tally parent
        if (debates[_arg.debate].arguments[_arg.argument].metadata.untalliedChilds == 0) {
            _tallyNode(DebateLib.Identifier({debate: _arg.debate, argument: parentId}));
        }
    } */
}
