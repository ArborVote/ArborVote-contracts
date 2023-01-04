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
    uint32 totalVotes; //     ┐   32 bits
    uint16 argumentsCount; // ┘ + 16 bits = 48 bits
    uint16[] leafArgumentIds;
    uint16[] disputedArgumentIds;
}

struct Argument {
    bytes32 contentURI;
    address creator; //         ┐  160 bits
    bool isSupporting; //       | +  8 bits
    State state; //             | +  8 bits
    uint16 parentArgumentId; // | + 16 bits
    uint16 untalliedChilds; //  | + 16 bits
    uint32 finalizationTime; // ┘ + 32 bits = 240 bits
    uint32 pro; //              ┐   32 bits
    uint32 con; //              | + 32 bits
    uint32 const; //            | + 32 bits // TODO remove
    uint32 vote; //             | + 32 bit
    uint32 fees; //             | + 32 bit
    uint32 childsVote; //       | + 32 bit
    int64 childsImpact; //      ┘ + 64 bits = 256 bits
} // 2 slots

enum State {
    Unitialized,
    Created,
    Final,
    Disputed,
    Invalid
}

struct InvestmentData {
    uint32 voteTokensInvested; // ┐   32 bits
    uint32 proMint; //            | + 32 bits
    uint32 conMint; //            | + 32 bits
    uint32 fee; //                | + 32 bits
    uint32 proSwap; //            | + 32 bits
    uint32 conSwap; //            ┘ + 32 bits = 192 bits
} // 1 slots

struct User {
    Role role; //     ┐    8 bits
    uint32 tokens; // ┘ + 32 bits = 40 bits
    mapping(uint16 => Shares) shares;
}

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
