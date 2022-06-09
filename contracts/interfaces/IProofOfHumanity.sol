//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// https://etherscan.io/address/0x1dAD862095d40d43c2109370121cf087632874dB#code

interface IProofOfHumanity {
    /** @dev Return true if the submission is registered and not expired.
     *  @param _submissionID The address of the submission.
     *  @return Whether the submission is registered or not.
     */
    function isRegistered(address _submissionID) external view returns (bool);

    /** @dev Return the number of submissions irrespective of their status.
     *  @return The number of submissions.
     */
    function submissionCounter() external view returns (uint256);
}
