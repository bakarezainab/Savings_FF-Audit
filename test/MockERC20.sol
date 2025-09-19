// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("IdealzToken", "IDZ") {
        _mint(msg.sender, 1_000_000 ether); // mint 1M tokens to deployer
    }
}