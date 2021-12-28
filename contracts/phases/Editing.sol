//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./../interfaces/IArbitrable.sol";
import "./../storage/HasStorage.sol";
import "./../utils/UtilsLib.sol";

contract Editing is HasStorage, IArbitrable {
    using SafeERC20 for ERC20;
    using UtilsLib for uint24;

    IArbitrator arbitrator;

    event Challenged(
        uint256 disputeId,
        DebateLib.Identifier id,
        bytes reason
    );

    event Resolved(
        uint256 disputeId,
        DebateLib.Identifier id
    );

    function finalizeArgument(DebateLib.Identifier memory _arg)
    public
    onlyArgumentState(_arg, DebateLib.State.Created)
    {
        require(debates.getArgumentFinalizationTime(_arg) <= uint32(block.timestamp));
        debates.setArgumentState(_arg, DebateLib.State.Final);
    }


    /*
     * @notice Create an argument with an initial approval
     */
    function addArgument(
        DebateLib.Identifier memory _parent,
        bytes32 _ipfsHash, bool _isSupporting,
        uint24 _initialApproval
    )
    onlyRole(_parent.debate, UserLib.Role.Participant)
    onlyArgumentState(_parent, DebateLib.State.Final)
    public
    {
        require(50 <= _initialApproval && _initialApproval <= 100);
        require(users.getUserTokens(_parent.debate, msg.sender) >= DebateLib.DEBATE_DEPOSIT);

        // initialize market
        DebateLib.Vault memory market;
        {
            // Create a child node and add it to the mapping
            users.spendVotesTokens(_parent.debate, msg.sender, DebateLib.DEBATE_DEPOSIT);
            (uint24 pro, uint24 con) = DebateLib.DEBATE_DEPOSIT.split(100 - _initialApproval, _initialApproval);
            market = DebateLib.Vault({
                pro : pro,
                con : con,
                const : pro*con,
                vote : DebateLib.DEBATE_DEPOSIT,
                fees : 0,
                ownImpact: 0 ,
                childsImpact: 0 });
        }

        uint32 finalizationTime;
        {
            finalizationTime = uint32(block.timestamp) + phases.getTimeUnit(_parent.debate);
        }

        DebateLib.Metadata memory metadata = DebateLib.Metadata({
            creator : msg.sender,
            finalizationTime: finalizationTime,
            //ownId : argumentId,
            parentId : _parent.argument,
            untalliedChilds : 0,
            isSupporting : _isSupporting,
            state : DebateLib.State.Created,
            disputeId: 0
        });

        debates.addArgument(_parent.debate, DebateLib.Argument({
            metadata: metadata,
            digest : _ipfsHash,
            market : market
        })
        );

    }

    function moveArgument(DebateLib.Identifier memory _arg, uint16 _newParentArgumentId) external
    onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
    onlyCreator(_arg)
    onlyArgumentState(_arg, DebateLib.State.Created)
    {
        // change old parent state (which eventually becomes a leaf because of the removal)
        {
            DebateLib.Identifier memory oldParent = debates.getParentId(_arg);
            require(debates.getArgumentState(oldParent) == DebateLib.State.Final);

            debates.decrementUntalliedChilds(oldParent);
            if(debates.getUntalliedChilds(oldParent) == 0)
                debates.appendLeafArgumentId(oldParent);
        }

        // change argument state
        debates.setParentId(_arg, _newParentArgumentId);

        // change new parent state
        debates.incrementUntalliedChilds(DebateLib.Identifier({debate: _arg.debate, argument: _newParentArgumentId}));
    }


   function alterArgument(DebateLib.Identifier memory _arg, bytes32 _ipfsHash) external
   onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
   onlyCreator(_arg)
   onlyArgumentState(_arg, DebateLib.State.Created)
   {

       uint32 newFinalizationTime = uint32(block.timestamp) + phases.getTimeUnit(_arg.debate);

       require(newFinalizationTime <= phases.getEditingEndTime(_arg.debate));

       debates.setFinalizationTime(_arg, newFinalizationTime);
       debates.setDigest(_arg, _ipfsHash);
   }


   function challenge(DebateLib.Identifier memory _arg, bytes calldata _reason) external
   onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
   onlyArgumentState(_arg, DebateLib.State.Final)
   returns (uint256 disputeId)
   {
       // create dispute
       {
           (address recipient, ERC20 feeToken, uint256 feeAmount) = arbitrator.getDisputeFees();
           // create dispute
           feeToken.safeTransferFrom(msg.sender, address(this), feeAmount);
           feeToken.safeApprove(recipient, feeAmount);
           disputeId = arbitrator.createDispute(2, abi.encodePacked(address(this), _arg.debate, _arg.argument)); // TODO 2 rulings?
           feeToken.safeApprove(recipient, 0); // reset just in case non-compliant tokens (that fail on non-zero to non-zero approvals) are used
       }

       // submit evidence
       {
           arbitrator.submitEvidence(disputeId, msg.sender,
               abi.encode(
                   debates.getDigest(_arg),
                   DebateLib.IPFS_HASH_FUNCTION,
                   DebateLib.IPFS_HASH_SIZE
               )
           );
           arbitrator.submitEvidence(disputeId, msg.sender, _reason);
           arbitrator.closeEvidencePeriod(disputeId);
       }

       // state changes
       debates.addDispute(_arg, disputeId);

       emit Challenged(disputeId, _arg, _reason);
   }


   function resolve(DebateLib.Identifier memory _arg) external
   onlyPhase(_arg.debate, PhaseLib.Phase.Editing)
   onlyArgumentState(_arg, DebateLib.State.Disputed)
   {
       uint256 disputeId = debates.getDisputeId(_arg);

       // fetch ruling
       (address subject, uint256 ruling) = arbitrator.rule(disputeId);
       require(subject == address(this));

       if(ruling == 0)
           debates.clearDispute(_arg, DebateLib.State.Final);
       else
           debates.clearDispute(_arg, DebateLib.State.Invalid);

       emit Ruled(arbitrator, disputeId, ruling);
       emit Resolved(disputeId, _arg);
   }
}
