//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../storage/HasStorage.sol";
import "./../utils/UtilsLib.sol";

contract Voting is HasStorage {
    using UtilsLib for uint16[];
    using UtilsLib for uint32;

    event Invested(
        address indexed buyer,
        DebateLib.Identifier indexed _arg,
        DebateLib.InvestmentData indexed data
    );

    // TODO add explanation
    function calculateSwap(uint32 _pro, uint32 _con, uint32 _swap) internal pure returns (uint32) {
        return _pro - _pro / (1 + _swap / _con);
        // TODO is this really always the order? Does this stem from the pair?
    }

    function calculateMint(DebateLib.Identifier memory _id, uint32 _voteTokenAmount)
    public view returns (DebateLib.InvestmentData memory data)
    {
        (uint32 pro, uint32 con) = debates.getArgumentTokens(_id);

        data.voteTokensInvested = _voteTokenAmount;

        data.fee = _voteTokenAmount.multipyByFraction(DebateLib.FEE_PERCENTAGE, 100);
        (uint32 proMint, uint32 conMint) = (_voteTokenAmount - data.fee).split(pro, con);

        data.proMint = proMint;
        data.conMint = conMint;

        data.proSwap = calculateSwap(proMint, conMint, conMint);
        data.conSwap = calculateSwap(proMint, conMint, proMint);
    }

    function investInPro(DebateLib.Identifier memory _arg, uint32 _amount) external
    onlyPhase(_arg.debate, PhaseLib.Phase.Voting)
    {
        require(users.getUserTokens(_arg.debate, msg.sender) >= _amount);
        users.spendVotesTokens(_arg.debate, msg.sender, _amount);

        DebateLib.InvestmentData memory data = calculateMint(_arg, _amount);
        debates.executeProInvestment(_arg, data);

        data.conSwap = 0;

        users.addProTokens(_arg, msg.sender, data.proMint + data.proSwap);


        emit Invested(msg.sender, _arg, data);
    }

    function investInCon(DebateLib.Identifier memory _arg, uint32 _amount) external
    onlyPhase(_arg.debate, PhaseLib.Phase.Voting)
    {
        require(users.getUserTokens(_arg.debate, msg.sender) >= _amount);
        users.spendVotesTokens(_arg.debate, msg.sender, _amount);

        DebateLib.InvestmentData memory data = calculateMint(_arg, _amount);
        debates.executeConInvestment(_arg, data);

        data.proSwap = 0;

        users.addConTokens(_arg, msg.sender, data.conMint + data.conSwap);

        emit Invested(msg.sender, _arg, data);
    }

}
