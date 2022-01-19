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

    error WrongPhase(PhaseLib.Phase expected, PhaseLib.Phase actual);
    error WrongState(DebateLib.State expected, DebateLib.State actual);
    error WrongRole(UserLib.Role expected, UserLib.Role actual);
    error WrongAddress(address expected, address actual);

    modifier onlyPhase(uint256 _debateId, PhaseLib.Phase _phase){
        if (phases.getPhase(_debateId) != _phase)
            revert WrongPhase({expected: _phase, actual: phases.getPhase(_debateId)});
        _;
    }
    modifier excludePhase(uint256 _debateId, PhaseLib.Phase _phase){
        if (phases.getPhase(_debateId) == _phase)
            revert WrongPhase({expected: _phase, actual: phases.getPhase(_debateId)});
        _;
    }

    modifier onlyArgumentState(DebateLib.Identifier memory _id, DebateLib.State _state){
        if (debates.getArgumentState(_id) != _state)
            revert WrongState({expected: _state, actual: debates.getArgumentState(_id)});
        _;
    }

    modifier onlyCreator(DebateLib.Identifier memory _id){
        if (msg.sender != debates.getCreator(_id))
            revert WrongAddress({expected: debates.getCreator(_id), actual: msg.sender});
        _;
    }

    modifier onlyRole(uint256 _debateId, UserLib.Role _role){
        if (users.getRole(_debateId, msg.sender) != _role)
            revert WrongRole({expected: _role, actual: users.getRole(_debateId, msg.sender)});
        _;
    }
}
