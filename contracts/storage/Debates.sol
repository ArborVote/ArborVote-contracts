//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./../utils/UtilsLib.sol";
import "./ACLHelper.sol";

library DebateLib {
    // https://docs.ipfs.io/concepts/content-addressing/
    // https://richardschneider.github.io/net-ipfs-core/articles/multihash.html
    uint8 constant IPFS_HASH_FUNCTION = 0x12; // sha2-256 - 256 bits (aka sha256),
    uint8 constant IPFS_HASH_SIZE = 0x20; // 32 bytes
    uint16 constant MAX_ARGUMENTS = type(uint16).max;

    // TODO make parameters
    int64 constant MIXING = 0x800000; // type(int64).max / 2

    uint32 constant DEBATE_DEPOSIT = 10;
    uint32 constant FEE_PERCENTAGE  = 5;

    enum State {Unitialized, Created, Final, Disputed, Invalid}

    struct Vault {
        uint32 pro; // 3 bytes
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
        address creator;         // 20 bytes
        uint32 finalizationTime; // 4 bytes
        uint16 parentId;         // 2 bytes
        uint16 untalliedChilds;  // 2 bytes
        bool isSupporting;       // 1 byte
        State state;             // 1 byte
        uint256 disputeId;       // 32 bytes // Todo cleaner way?
    }

    struct Argument {
        Metadata metadata;       // 64 bytes
        bytes32 digest;          // 32 bytes
        Vault market;            // 32 Bytes

    } // 3x 32 bytes

    struct Multihash {
        bytes32 digest;
        uint8 hashFunction;
        uint8 size;
    }

    function getMultihash(Argument storage _argument) public view returns (Multihash memory){
        return Multihash(_argument.digest, IPFS_HASH_FUNCTION, IPFS_HASH_SIZE);
    }

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

contract Debates is ACLHelper{
    using UtilsLib for uint16[];

    address private arborVote;
    address private editing;
    address private voting;
    address private tallying;

    uint240 public debatesCount;
    mapping(uint240 => DebateLib.Debate ) public debates;

    function initialize(
        address _editing,
        address _voting,
        address _tallying
    ) external initializer {
        initACL(msg.sender);
        arborVote = msg.sender;
        editing = _editing;
        voting = _voting;
        tallying = _tallying;

        _grant(address(this), arborVote, STORAGE_CHANGE_ROLE);
        _grant(address(this), editing, STORAGE_CHANGE_ROLE);
        _grant(address(this), voting, STORAGE_CHANGE_ROLE);
        _grant(address(this), tallying, STORAGE_CHANGE_ROLE);
    }

    function executeProInvestment(DebateLib.Identifier memory _id, DebateLib.InvestmentData memory data)
    external
    onlyFromContract(voting)
    {
        debates[_id.debate].arguments[_id.argument].market.vote += data.voteTokensInvested - data.fee;
        debates[_id.debate].arguments[_id.argument].market.fees += data.fee;
        debates[_id.debate].arguments[_id.argument].market.con += data.conMint;
        debates[_id.debate].arguments[_id.argument].market.pro -= data.proSwap;
    }

    function executeConInvestment(DebateLib.Identifier memory _id, DebateLib.InvestmentData memory data)
    external
    onlyFromContract(voting)
    {
        debates[_id.debate].arguments[_id.argument].market.vote += data.voteTokensInvested - data.fee;
        debates[_id.debate].arguments[_id.argument].market.fees += data.fee;
        debates[_id.debate].arguments[_id.argument].market.pro += data.proMint;
        debates[_id.debate].arguments[_id.argument].market.con -= data.conSwap;
    }

    function getArgumentTokens(DebateLib.Identifier memory _id) public view returns (uint32 pro, uint32 con){
        pro = debates[_id.debate].arguments[_id.argument].market.pro;
        con = debates[_id.debate].arguments[_id.argument].market.con;
    }

    function getChildsImpact(DebateLib.Identifier memory _id) public view returns (int64){
        return debates[_id.debate].arguments[_id.argument].market.childsImpact;
    }

    function getDigest(DebateLib.Identifier memory _id) public view returns (bytes32){
        return debates[_id.debate].arguments[_id.argument].digest;
    }

    function getArgumentState(DebateLib.Identifier memory _id) public view returns (DebateLib.State){
        return debates[_id.debate].arguments[_id.argument].metadata.state;
    }

    function isSupporting(DebateLib.Identifier memory _id) public view returns (bool){
        return debates[_id.debate].arguments[_id.argument].metadata.isSupporting;
    }

    function getParentId(DebateLib.Identifier memory _id) public view returns (DebateLib.Identifier memory){
        return DebateLib.Identifier({
            debate: _id.debate,
            argument: debates[_id.debate].arguments[_id.argument].metadata.parentId
        });
    }

    function getDisputeId(DebateLib.Identifier memory _id) public view returns (uint256){
        return debates[_id.debate].arguments[_id.argument].metadata.disputeId;
    }

    function getDisputedArgumentsCount(uint240 _debateId) public view returns (uint256){
        return debates[_debateId].disputedArgumentIds.length;
    }

    function getLeafArgumentIds(uint240 _debateId) public view returns (uint16[] memory){
        return debates[_debateId].leafArgumentIds;
    }

    function getUntalliedChilds(DebateLib.Identifier memory _id) public view returns (uint16){
        return debates[_id.debate].arguments[_id.argument].metadata.untalliedChilds;
    }

    function getArgumentFinalizationTime(DebateLib.Identifier memory _id) public view returns (uint32){
        return debates[_id.debate].arguments[_id.argument].metadata.finalizationTime;
    }

    function getCreator(DebateLib.Identifier memory _id) public view returns (address) {
        return debates[_id.debate].arguments[_id.argument].metadata.creator;
    }



    function initializeDebate(DebateLib.Argument memory rootArgument)
    external
    onlyFromContract(arborVote)
    {
        debates[debatesCount].arguments[0] = rootArgument;
        // increment counters
        debates[debatesCount].argumentsCount++;
        debatesCount++;
    }


    function addArgument(uint240 _debateId, DebateLib.Argument memory _argument
    )
    external
    onlyFromContract(editing)
    {
        debates[_debateId].arguments[debates[_debateId].argumentsCount] = _argument;

        debates[_debateId].leafArgumentIds.removeById(_argument.metadata.parentId);
        debates[_debateId].arguments[_argument.metadata.parentId].metadata.untalliedChilds++;
        debates[_debateId].leafArgumentIds.push(debates[_debateId].argumentsCount);
        debates[_debateId].argumentsCount++;
    }

    function setArgumentState(DebateLib.Identifier memory _id, DebateLib.State _state)
    external
    onlyFromContract(editing)
    {
        debates[_id.debate].arguments[_id.argument].metadata.state = _state;
    }

    function addDispute(DebateLib.Identifier memory _id, uint256 _disputeId)
    external
    onlyFromContract(editing)
    {
        debates[_id.debate].arguments[_id.argument].metadata.state = DebateLib.State.Disputed;
        debates[_id.debate].arguments[_id.argument].metadata.disputeId = _disputeId;
        debates[_id.debate].disputedArgumentIds.push(_id.argument);
    }

    function clearDispute(DebateLib.Identifier memory _id, DebateLib.State _state)
    external
    onlyFromContract(editing)
    {
        debates[_id.debate].arguments[_id.argument].metadata.state = _state;
        debates[_id.debate].disputedArgumentIds.removeById(_id.argument);
    }

    function setParentId(DebateLib.Identifier memory _id, uint16 _parentArgumentId)
    external
    onlyFromContract(editing)
    {
        debates[_id.debate].arguments[_id.argument].metadata.parentId = _parentArgumentId;
    }

    function setFinalizationTime(DebateLib.Identifier memory _id, uint32 _finalizationTime)
    external
    onlyFromContract(editing)
    {
        debates[_id.debate].arguments[_id.argument].metadata.finalizationTime = _finalizationTime;
    }

    function setDigest(DebateLib.Identifier memory _id, bytes32 _digest)
    external
    onlyFromContract(editing)
    {
        debates[_id.debate].arguments[_id.argument].digest = _digest;
    }

    function appendLeafArgumentId(DebateLib.Identifier memory _id)
    external
    onlyFromContract(editing)
    {
        debates[_id.debate].leafArgumentIds.push(_id.argument);
    }

    function addChildImpact(DebateLib.Identifier memory _id, int64 _childImpact)
    external
    onlyFromContract(tallying)
    {
        debates[_id.debate].arguments[_id.argument].market.childsImpact += _childImpact;
    }

    function incrementUntalliedChilds(DebateLib.Identifier memory _id) external
    onlyFromContract(editing)
    {
        debates[_id.debate].arguments[_id.argument].metadata.untalliedChilds++;
    }

    function decrementUntalliedChilds(DebateLib.Identifier memory _id) external
    onlyFromTwoContracts(editing, tallying)
    {
        debates[_id.debate].arguments[_id.argument].metadata.untalliedChilds--;
    }
}
