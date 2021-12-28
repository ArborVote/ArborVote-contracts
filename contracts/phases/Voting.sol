//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../storage/HasStorage.sol";
import "./../utils/UtilsLib.sol";

contract Voting is HasStorage {
    using UtilsLib for uint16[];
    using UtilsLib for uint24;

    event Invested(
        address indexed buyer,
        DebateLib.Identifier indexed _arg,
        DebateLib.InvestmentData indexed data
    );

    // TODO add explanation
    function calculateSwap(uint24 _pro, uint24 _con, uint24 _swap) internal pure returns (uint24) {
        return _pro - _pro / (1 + _swap / _con);
        // TODO is this really always the order? Does this stem from the pair?
    }

    function calculateMint(DebateLib.Identifier memory _id, uint24 _voteTokenAmount)
    public view returns (DebateLib.InvestmentData memory data)
    {
        (uint24 pro, uint24 con) = debates.getArgumentTokens(_id);

        data.voteTokensInvested = _voteTokenAmount;

        data.fee = _voteTokenAmount.multipyByFraction(DebateLib.FEE_PERCENTAGE, 100);
        (uint24 proMint, uint24 conMint) = (_voteTokenAmount - data.fee).split(pro, con);

        data.proMint = proMint;
        data.conMint = conMint;

        data.proSwap = calculateSwap(proMint, conMint, conMint);
        data.conSwap = calculateSwap(proMint, conMint, proMint);
    }

    function investInPro(DebateLib.Identifier memory _arg, uint24 _amount) external
    onlyPhase(_arg.debate, PhaseLib.Phase.Voting)
    {
        require(users.getUserTokens(_arg.debate, msg.sender) >= _amount);
        users.spendVotesTokens(_arg.debate, msg.sender, _amount);

        DebateLib.InvestmentData memory data = calculateMint(_arg, _amount);
        debates.executeProInvestment(_arg, data);

        users.addProTokens(_arg, msg.sender, data.proMint + data.proSwap);

        data.conSwap = 0;
        emit Invested(msg.sender, _arg, data);
    }

    function investInCon(DebateLib.Identifier memory _arg, uint24 _amount) external
    onlyPhase(_arg.debate, PhaseLib.Phase.Voting)
    {
        require(users.getUserTokens(_arg.debate, msg.sender) >= _amount);
        users.spendVotesTokens(_arg.debate, msg.sender, _amount);

        DebateLib.InvestmentData memory data = calculateMint(_arg, _amount);
        debates.executeConInvestment(_arg, data);

        users.addConTokens(_arg, msg.sender, data.conMint + data.conSwap);

        data.proSwap = 0;
        emit Invested(msg.sender, _arg, data);
    }

}
