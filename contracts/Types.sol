//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Debate {
    mapping(uint16 => Argument) arguments;
    uint32 totalVotes;
    uint16 argumentsCount;
    uint16[] leafArgumentIds;
    uint16[] disputedArgumentIds;
}

struct Argument {
    Metadata metadata;
    bytes32 contentURI;
    Market market;
} // 1024 bits = 4x 32 bytes

struct Market {
    uint32 pro;
    uint32 con;
    uint32 const;
    uint32 vote;
    uint32 fees;
} // 160 bits < 32 bytes

struct Metadata {
    address creator; // 160 bits = 20 bytes
    uint32 finalizationTime;
    uint16 parenArgumentId;
    uint16 untalliedChilds;
    uint32 childsVote;
    // 256 bits
    int64 childsImpact;
    bool isSupporting;
    State state;
    // 80 bits
} // 336 bits < 2x 32 bytes

enum State {
    Unitialized,
    Created,
    Final,
    Disputed,
    Invalid
}

struct InvestmentData {
    uint32 voteTokensInvested;
    uint32 proMint;
    uint32 conMint;
    uint32 fee;
    uint32 proSwap;
    uint32 conSwap;
} // 192 bits

struct User {
    Role role;
    uint32 tokens;
    mapping(uint16 => Shares) shares;
} // 296 bits

enum Role {
    Unassigned,
    Participant,
    Juror
}

struct Shares {
    uint32 pro;
    uint32 con;
} // 64 bits

struct PhaseData {
    Phase currentPhase;
    uint32 editingEndTime;
    uint32 votingEndTime;
    uint32 timeUnit;
} // 104 bits

enum Phase {
    Unitialized,
    Editing,
    Voting,
    Finished
}
