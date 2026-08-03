// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply reward token for Baro's GIWA Sepolia quest pilot.
/// @dev This token has no minting authority and has no value outside the testnet pilot.
contract BaroQuestTestToken is ERC20 {
    error InvalidRecipient();
    error InvalidSupply();

    constructor(address recipient, uint256 initialSupply) ERC20("Baro Quest Test Token", "BQT") {
        if (recipient == address(0)) revert InvalidRecipient();
        if (initialSupply == 0) revert InvalidSupply();
        _mint(recipient, initialSupply);
    }
}
