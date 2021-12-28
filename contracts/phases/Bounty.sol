//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../storage/HasStorage.sol";

library BountyLib {
}

contract Bounty is HasStorage{
    using SafeERC20 for ERC20;
    IERC20 bounty;

    function redeem(uint256 _debateId, uint16 _argumentId) public {
        // TODO redeem pro and con of msg.sender for votes
    }

    function withdrawBounty() public {
        // TODO
    }
}