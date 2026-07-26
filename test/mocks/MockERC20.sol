// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { BaroCampaignEscrow } from "../../src/BaroCampaignEscrow.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Reward", "MRWD") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract NonReceiverWallet {
    receive() external payable { }

    function claim(
        BaroCampaignEscrow escrow,
        BaroCampaignEscrow.QuestClaim calldata voucher,
        address signer,
        bytes calldata signature
    ) external {
        escrow.claimReward(voucher, signer, signature);
    }
}
