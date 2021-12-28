//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../storage/HasStorage.sol";
import "./../utils/UtilsLib.sol";

contract Tallying is HasStorage {
    using UtilsLib for int48;
    using UtilsLib for uint24;

    function tallyTree(uint240 _debateId)
    public
    onlyPhase(_debateId, PhaseLib.Phase.Finished)
    {
        require(debates.getDisputedArgumentsCount(_debateId) == 0);

        uint16[] memory leafArgumentIds = debates.getLeafArgumentIds(_debateId);

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            tallyNode(DebateLib.Identifier({debate: _debateId, argument: leafArgumentIds[i]}));
        }
    }

    function calculateOwnImpact(DebateLib.Identifier memory _arg)
    internal view
    returns(int48 own)
    {
        (uint24 pro, uint24 con) = debates.getArgumentTokens(_arg);

        // calculate own impact
        own = int48(uint48(type(uint24).max.multipyByFraction(pro, pro + con)));

        own = own.multipyByFraction(type(int48).max - int48(DebateLib.MIXING), type(int48).max)
        + (debates.getChildsImpact(_arg)).multipyByFraction(int48(DebateLib.MIXING), type(int48).max);

        if(debates.isSupporting(_arg))
            own = -own;
    }

    function tallyNode(DebateLib.Identifier memory _arg)
    internal
    {
        require(debates.getUntalliedChilds(_arg) == 0); // All childs must be tallied first

        int48 own = calculateOwnImpact(_arg);

        // Change parent state
        DebateLib.Identifier memory parent = debates.getParentId(_arg);
        // TODO weight calculation

        debates.addChildImpact(parent, own);
        debates.decrementUntalliedChilds(parent);

        // if all childs of the parent are tallied, tally parent
        if (debates.getUntalliedChilds(parent) == 0)
            tallyNode(parent);
    }
}
