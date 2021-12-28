//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockArbitrator is ERC20 {
    constructor(uint256 _initialSupply, address _beneficiary) ERC20("Mock ERC20 Token", "MCK") {
        _mint(_beneficiary, _initialSupply);
    }
}