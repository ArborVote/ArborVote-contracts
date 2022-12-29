//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

library DebateLib {
    function incrementArgumentCounter(Debate storage _debate) internal {
        _debate.argumentsCount += 1;
    }

    function getArgumentsCount(Debate storage _debate) internal view returns (uint16) {
        return _debate.argumentsCount;
    }
}

struct Debate {
    mapping(uint16 => Argument) arguments;
    uint32 totalVotes;
    uint16 argumentsCount;
    uint16[] leafArgumentIds;
    uint16[] disputedArgumentIds;
}

struct Argument {
    bytes32 contentURI; // 256 bits
    // - SLOT 1 END -
    address creator; // 160 bits = 20 bytes
    bool isSupporting; // 8 bits
    State state; // 8 bits
    uint16 parentArgumentId;
    uint16 untalliedChilds;
    uint32 finalizationTime;
    // 240 bits
    // - SLOT 2 END -
    uint32 pro;
    uint32 con;
    uint32 const; // TODO remove
    uint32 vote;
    uint32 fees;
    uint32 childsVote;
    int64 childsImpact;
    // - SLOT 3 END -
}

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
