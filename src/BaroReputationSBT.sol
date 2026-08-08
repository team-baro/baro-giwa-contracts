// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { IBaroReputationSBT } from "./interfaces/IBaroReputationSBT.sol";

/// @title BaroReputationSBT
/// @notice Non-transferable ERC-721 recording each user's quest and channel history.
/// @dev Soulbound in both directions: transfer approvals revert outright, and {_update}
///      rejects any movement of a token that already has an owner. Minting is implicit —
///      a user's token is created the first time the escrow or an operator writes to them,
///      so no separate opt-in step is needed.
contract BaroReputationSBT is ERC721, AccessControlDefaultAdminRules, IBaroReputationSBT {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Held by {BaroCampaignEscrow}; the only role that may record quest completions.
    bytes32 public constant ESCROW_ROLE = keccak256("ESCROW_ROLE");

    /// @notice Records off-chain channel verification results.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Manages the token base URI.
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A user's accumulated reputation.
    /// @dev Packs into a single storage slot: 4 x uint64 + uint32 + bool = 100 bits spare.
    struct Reputation {
        uint64 questPoints;
        uint64 questCount;
        uint64 campaignCount;
        uint64 lastUpdated;
        uint32 channelScore;
        bool isChannelVerified;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error Soulbound();
    error ScoreOutOfRange();
    error InvalidPoints();
    error CompletionAlreadyRecorded();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ReputationMinted(address indexed user, uint256 indexed tokenId);
    event QuestCompletionRecorded(
        address indexed user,
        uint256 indexed campaignId,
        uint256 indexed questId,
        uint32 points,
        uint64 questPoints,
        uint64 questCount,
        uint64 campaignCount,
        uint64 completedAt
    );
    event ChannelVerificationUpdated(address indexed user, bool isVerified, uint32 channelScore);
    event BaseURIUpdated(string baseURI);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    // NOTE: declaration order below is the contract's storage layout. Do not reorder.

    /// @notice Accumulated reputation per user.
    mapping(address user => Reputation reputation) public reputations;

    /// @notice Each user's SBT id. Zero means no token has been minted yet.
    mapping(address user => uint256 tokenId) public tokenIds;

    /// @notice Whether a user has been counted towards a campaign, so `campaignCount`
    ///         increments once per campaign rather than once per quest.
    mapping(address user => mapping(uint256 campaignId => bool participated)) public
        hasParticipatedInCampaign;

    /// @notice Quest completions already recorded, making {recordQuestCompletion} idempotent
    ///         against retries from the escrow's deferred-update path.
    mapping(
        address user => mapping(uint256 campaignId => mapping(uint256 questId => bool recorded))
    ) public recordedCompletions;

    /// @dev Next SBT id. Starts at 1 so 0 stays a "not minted" sentinel in {tokenIds}.
    uint256 private _nextTokenId = 1;

    /// @dev Base URI prefix returned by {_baseURI}.
    string private _baseTokenUri;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param admin Default admin, subject to the 1 day {AccessControlDefaultAdminRules} delay.
    /// @param operator Address allowed to record channel verification.
    /// @param escrow {BaroCampaignEscrow} instance allowed to record quest completions.
    /// @param baseTokenURI Initial metadata base URI.
    constructor(address admin, address operator, address escrow, string memory baseTokenURI)
        ERC721("Baro Reputation", "BARO-SBT")
        AccessControlDefaultAdminRules(1 days, admin)
    {
        if (admin == address(0) || operator == address(0) || escrow == address(0)) {
            revert InvalidAddress();
        }

        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(ESCROW_ROLE, escrow);
        _grantRole(METADATA_ROLE, admin);

        _baseTokenUri = baseTokenURI;
    }

    /*//////////////////////////////////////////////////////////////
                            QUEST REPUTATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Credits a completed quest to a user, minting their SBT if this is their first.
    /// @dev Restricted to {ESCROW_ROLE} so reputation can only be earned through a real payout.
    ///      Re-recording the same quest reverts, which keeps the escrow's retry path safe.
    /// @param user User who completed the quest.
    /// @param campaignId Campaign the quest belongs to.
    /// @param questId Quest completed.
    /// @param points Reputation points to credit.
    function recordQuestCompletion(address user, uint256 campaignId, uint256 questId, uint32 points)
        external
        override
        onlyRole(ESCROW_ROLE)
    {
        // Checks.
        if (user == address(0)) revert InvalidAddress();
        if (points == 0) revert InvalidPoints();
        if (recordedCompletions[user][campaignId][questId]) {
            revert CompletionAlreadyRecorded();
        }

        _mintIfNeeded(user);

        // Effects.
        Reputation storage reputation = reputations[user];
        recordedCompletions[user][campaignId][questId] = true;
        reputation.questPoints += points;
        reputation.questCount += 1;

        // A campaign counts once, no matter how many of its quests the user finishes.
        if (!hasParticipatedInCampaign[user][campaignId]) {
            hasParticipatedInCampaign[user][campaignId] = true;
            reputation.campaignCount += 1;
        }

        uint64 completedAt = uint64(block.timestamp);
        reputation.lastUpdated = completedAt;

        emit QuestCompletionRecorded(
            user,
            campaignId,
            questId,
            points,
            reputation.questPoints,
            reputation.questCount,
            reputation.campaignCount,
            completedAt
        );
    }

    /*//////////////////////////////////////////////////////////////
                          CHANNEL VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Marks a user's channel as verified with a score.
    /// @param user User to verify.
    /// @param channelScore Score in the range 0-100.
    function verifyChannel(address user, uint32 channelScore) external onlyRole(OPERATOR_ROLE) {
        _setChannelVerification(user, true, channelScore);
    }

    /// @notice Clears a user's channel verification and resets their score to zero.
    /// @param user User to revoke.
    function revokeChannelVerification(address user) external onlyRole(OPERATOR_ROLE) {
        _setChannelVerification(user, false, 0);
    }

    /// @notice Sets channel verification and score in one call.
    /// @dev An unverified user must carry a zero score, so the two fields cannot disagree.
    /// @param user User to update.
    /// @param isVerified Whether the channel is verified.
    /// @param channelScore Score in the range 0-100; must be zero when `isVerified` is false.
    function setChannelVerification(address user, bool isVerified, uint32 channelScore)
        external
        onlyRole(OPERATOR_ROLE)
    {
        _setChannelVerification(user, isVerified, channelScore);
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the metadata base URI for every token.
    /// @param baseTokenURI New base URI.
    function setBaseURI(string calldata baseTokenURI) external onlyRole(METADATA_ROLE) {
        _baseTokenUri = baseTokenURI;

        emit BaseURIUpdated(baseTokenURI);
    }

    /// @inheritdoc ERC721
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControlDefaultAdminRules)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                          SOULBOUND ENFORCEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Disabled. Reputation tokens cannot be approved for transfer.
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    /// @notice Disabled. Reputation tokens cannot be approved for transfer.
    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    /// @dev Single choke point for every mint, transfer, and burn in ERC-721. Allowing only
    ///      the case where the token has no current owner permits minting while blocking
    ///      transfers and burns, which is what makes the token soulbound.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address previousOwner)
    {
        previousOwner = _ownerOf(tokenId);
        if (previousOwner != address(0)) revert Soulbound();

        return super._update(to, tokenId, auth);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Shared implementation behind the three channel verification entry points.
    function _setChannelVerification(address user, bool isVerified, uint32 channelScore) private {
        // Checks.
        if (user == address(0)) revert InvalidAddress();
        if (channelScore > 100) revert ScoreOutOfRange();
        if (!isVerified && channelScore != 0) revert ScoreOutOfRange();

        _mintIfNeeded(user);

        // Effects.
        Reputation storage reputation = reputations[user];
        reputation.isChannelVerified = isVerified;
        reputation.channelScore = channelScore;
        reputation.lastUpdated = uint64(block.timestamp);

        emit ChannelVerificationUpdated(user, isVerified, channelScore);
    }

    /// @dev Mints the user's SBT on first write. No-op once they already hold one.
    function _mintIfNeeded(address user) private {
        if (tokenIds[user] != 0) return;

        uint256 tokenId = _nextTokenId++;
        tokenIds[user] = tokenId;
        _mint(user, tokenId);

        emit ReputationMinted(user, tokenId);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenUri;
    }
}
