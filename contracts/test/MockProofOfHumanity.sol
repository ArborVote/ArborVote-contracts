//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IProofOfHumanity.sol";

contract MockProofOfHumanity is IProofOfHumanity {
    function isRegistered(address _submissionID) external pure returns (bool) {
        (_submissionID);
        return true;
    }

    function submissionCounter() external pure returns (uint256) {
        return 1;
    }
}
