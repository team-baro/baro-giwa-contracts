// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IBaroReputationSBT {
    function recordQuestCompletion(address user, uint256 campaignId) external;
}

