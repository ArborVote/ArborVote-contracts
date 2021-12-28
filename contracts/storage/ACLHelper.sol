//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../acl/ACL.sol";

contract ACLHelper is ACL {
    bytes32 public constant STORAGE_CHANGE_ROLE = keccak256("STORAGE_CHANGE_ROLE");

    modifier onlyFromContract(address _contract){
        // TODO: this needs to be specific for every debate
        require(_checkRole(address(this), _contract, STORAGE_CHANGE_ROLE, msg.data));
        _;
    }

    modifier onlyFromTwoContracts(address _contract1, address _contract2){
        // TODO: this needs to be specific for every debate
        require(_checkRole(address(this), _contract1, STORAGE_CHANGE_ROLE, msg.data)
            || _checkRole(address(this), _contract2, STORAGE_CHANGE_ROLE, msg.data));
        _;
    }
}
