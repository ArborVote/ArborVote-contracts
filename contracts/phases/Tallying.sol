//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../storage/HasStorage.sol";
import "./../utils/UtilsLib.sol";

contract Tallying is HasStorage {
    using UtilsLib for int64;
    using UtilsLib for uint32;

    function tallyTree(uint240 _debateId)
        public
        onlyPhase(_debateId, PhaseLib.Phase.Finished)
    {
        require(debates.getDisputedArgumentsCount(_debateId) == 0);

        uint16[] memory leafArgumentIds = debates.getLeafArgumentIds(_debateId);

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            tallyNode(
                DebateLib.Identifier({
                    debate: _debateId,
                    argument: leafArgumentIds[i]
                })
            );
        }

        phases.setFinished(_debateId);
    }

    function calculateOwnImpact(DebateLib.Identifier memory _arg)
        internal
        view
        returns (int64 own)
    {
        (uint32 pro, uint32 con) = debates.getArgumentTokens(_arg);

        // calculate own impact
        own = int64(uint64(type(uint32).max.multipyByFraction(pro, pro + con)));

        own =
            own.multipyByFraction(
                type(int64).max - int64(DebateLib.MIXING),
                type(int64).max
            ) +
            (debates.getChildsImpact(_arg)).multipyByFraction(
                int64(DebateLib.MIXING),
                type(int64).max
            );

        if (debates.isSupporting(_arg)) own = -own;
    }

    function tallyNode(DebateLib.Identifier memory _arg) internal {
        require(debates.getUntalliedChilds(_arg) == 0); // All childs must be tallied first

        int64 own = calculateOwnImpact(_arg);

        // Change parent state
        DebateLib.Identifier memory parent = debates.getParentId(_arg);
        // TODO weight calculation

        debates.addChildImpact(parent, own);
        debates.decrementUntalliedChilds(parent);

        // if all childs of the parent are tallied, tally parent
        if (debates.getUntalliedChilds(parent) == 0) tallyNode(parent);
    }
}
