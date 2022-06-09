//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../test/MockERC20.sol";
import "../interfaces/IArbitrable.sol";

contract MockArbitrator is IArbitrator {
    MockERC20 private token;

    function createDispute(uint256 _possiblerRulings, bytes calldata _metadata)
        external
        returns (uint256)
    {
        return 0;
    }

    function submitEvidence(
        uint256 _disputeId,
        address _submitter,
        bytes calldata _evidence
    ) external {}

    function closeEvidencePeriod(uint256 _disputeId) external {}

    function rule(uint256 _disputeId) external returns (address subject, uint256 ruling) {
        subject = address(0);
        ruling = 0;
    }

    function getDisputeFees()
        external
        view
        returns (
            address recipient,
            ERC20 feeToken,
            uint256 feeAmount
        )
    {
        recipient = address(0);
        feeToken = token;
        feeAmount = 123;
    }

    function getPaymentsRecipient() external view returns (address) {
        return address(0);
    }
}
