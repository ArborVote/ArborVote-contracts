//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * Debate Related
 */

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

/**
 * Argument Related
 */

enum State {
    Unitialized,
    Created,
    Final,
    Disputed,
    Invalid
}

struct Argument {
    bytes32 contentURI;
    address creator; //         ┐  160 bits
    bool isSupporting; //       | +  8 bits
    State state; //             | +  8 bits
    uint16 parentArgumentId; // | + 16 bits
    uint16 untalliedChilds; //  | + 16 bits
    uint64 finalizationTime; // ┘ + 64 bits = 256 bits
    uint32 pro; //              ┐   32 bits
    uint32 con; //              | + 32 bits
    uint32 const; //            | + 32 bits // TODO remove
    uint32 vote; //             | + 32 bit
    uint32 fees; //             | + 32 bit
    uint32 childsVote; //       | + 32 bit
    int64 childsImpact; //      ┘ + 64 bits = 256 bits
} // 2 slots

struct InvestmentData {
    uint32 voteTokensInvested; // ┐   32 bits
    uint32 proMint; //            | + 32 bits
    uint32 conMint; //            | + 32 bits
    uint32 fee; //                | + 32 bits
    uint32 proSwap; //            | + 32 bits
    uint32 conSwap; //            ┘ + 32 bits = 192 bits
} // 1 slot

/**
 * User Related
 */

enum Role {
    Unassigned,
    Participant,
    Juror
}

struct User {
    Role role; //     ┐    8 bits
    uint32 tokens; // ┘ + 32 bits = 40 bits
    mapping(uint16 => Shares) shares;
} // 2 slots

struct Shares {
    uint32 pro; // ┐   32 bits
    uint32 con; // ┘ + 32 bits = 64 bits
} // 1 slot

/**
 * Time Related
 */

enum Phase {
    Unitialized,
    Editing,
    Voting,
    Finished
}

struct PhaseData {
    Phase currentPhase; //    ┐    8 bits
    uint64 editingEndTime; // | + 64 bits
    uint64 votingEndTime; //  | + 64 bits
    uint64 timeUnit; //       ┘ + 64 bits = 194 bits
} // 1 slot
