// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice The slice of {BaroReputationSBT} that {BaroCampaignEscrow} depends on.
/// @dev Kept deliberately minimal so the escrow can be pointed at a replacement SBT
///      implementation without inheriting the full ERC-721 surface.
interface IBaroReputationSBT {
    /// @notice Credits a completed quest to a user's reputation.
    /// @param user User who completed the quest.
    /// @param campaignId Campaign the quest belongs to.
    /// @param questId Quest completed.
    /// @param points Reputation points to credit.
    function recordQuestCompletion(address user, uint256 campaignId, uint256 questId, uint32 points)
        external;
}
