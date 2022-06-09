//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./ACLHelper.sol";

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

contract Phases is Initializable, ACLHelper {
    address private arborVote;
    address private tallying;

    mapping(uint256 => PhaseLib.PhaseData) public phases;

    function initialize(address _tallying) external initializer {
        initACL(msg.sender);
        arborVote = msg.sender;
        tallying = _tallying;

        _grant(address(this), arborVote, STORAGE_CHANGE_ROLE);
        _grant(address(this), tallying, STORAGE_CHANGE_ROLE);
    }

    function getTimeUnit(uint256 _debateId) public view returns (uint32) {
        return phases[_debateId].timeUnit;
    }

    function getEditingEndTime(uint256 _debateId) public view returns (uint32) {
        return phases[_debateId].editingEndTime;
    }

    function getPhase(uint256 _debateId) public view returns (PhaseLib.Phase) {
        return phases[_debateId].currentPhase;
    }

    function initializePhases(uint256 _debateId, uint32 _timeUnit)
        external
        onlyFromContract(arborVote)
    {
        phases[_debateId].currentPhase = PhaseLib.Phase.Editing;
        phases[_debateId].timeUnit = _timeUnit;
        phases[_debateId].editingEndTime = uint32(block.timestamp + 7 * _timeUnit);
        phases[_debateId].votingEndTime = uint32(block.timestamp + 10 * _timeUnit);
    }

    function updatePhase(uint240 _debateId) external onlyFromContract(arborVote) {
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

    function setFinished(uint240 _debateId) external onlyFromContract(tallying) {
        phases[_debateId].currentPhase = PhaseLib.Phase.Finished;
    }
}
