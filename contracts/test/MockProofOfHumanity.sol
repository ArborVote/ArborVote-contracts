//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IProofOfHumanity.sol";

contract MockProofOfHumanity is IProofOfHumanity  {
    function isRegistered(address _submissionID) external view returns (bool) {
        return true;
    }

    function submissionCounter() external view returns (uint){
        return 1;
    }
}