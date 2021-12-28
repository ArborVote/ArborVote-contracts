//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./Phases.sol";
import "./Debates.sol";
import "./Users.sol";

contract HasStorage is Initializable {
    Phases phases;
    Debates debates;
    Users users;

    function initializeStorage(
        address _phases,
        address _debates,
        address _users
    )
    external
    initializer
    {
        phases = Phases(_phases);
        debates = Debates(_debates);
        users = Users(_users);
    }

    modifier onlyPhase(uint256 _debateId, PhaseLib.Phase _phase){
        require(phases.getPhase(_debateId) == _phase);
        _;
    }
    modifier excludePhase(uint256 _debateId, PhaseLib.Phase _phase){
        require(phases.getPhase(_debateId) != _phase);
        _;
    }

    modifier onlyArgumentState(DebateLib.Identifier memory _id, DebateLib.State _state){
        require(debates.getArgumentState(_id) == _state);
        _;
    }

    modifier onlyCreator(DebateLib.Identifier memory _id){
        require(debates.getCreator(_id) == msg.sender);
        _;
    }

    modifier onlyRole(uint256 _debateId, UserLib.Role _role){
        require(users.getRole(_debateId, msg.sender) == _role);
        _;
    }


}
