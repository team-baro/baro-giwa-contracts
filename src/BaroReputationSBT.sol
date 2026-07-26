// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { IBaroReputationSBT } from "./interfaces/IBaroReputationSBT.sol";

contract BaroReputationSBT is ERC721, AccessControl, IBaroReputationSBT {
    bytes32 public constant ESCROW_ROLE = keccak256("ESCROW_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct Reputation {
        uint64 questCount;
        uint64 campaignCount;
        uint64 lastUpdated;
        uint32 channelScore;
        bool isChannelVerified;
    }

    error InvalidAddress();
    error Soulbound();
    error ScoreOutOfRange();

    event ReputationMinted(address indexed user, uint256 indexed tokenId);
    event QuestCompletionRecorded(
        address indexed user, uint256 indexed campaignId, uint64 questCount, uint64 campaignCount
    );
    event ChannelVerified(address indexed user, uint32 channelScore);

    mapping(address user => Reputation reputation) public reputations;
    mapping(address user => uint256 tokenId) public tokenIds;
    mapping(address user => mapping(uint256 campaignId => bool participated)) public
        hasParticipatedInCampaign;

    uint256 private _nextTokenId = 1;

    constructor(address admin, address operator) ERC721("Baro Reputation", "BARO-SBT") {
        if (admin == address(0) || operator == address(0)) revert InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }

    function recordQuestCompletion(address user, uint256 campaignId)
        external
        override
        onlyRole(ESCROW_ROLE)
    {
        if (user == address(0)) revert InvalidAddress();
        _mintIfNeeded(user);

        Reputation storage reputation = reputations[user];
        reputation.questCount += 1;
        if (!hasParticipatedInCampaign[user][campaignId]) {
            hasParticipatedInCampaign[user][campaignId] = true;
            reputation.campaignCount += 1;
        }
        reputation.lastUpdated = uint64(block.timestamp);

        emit QuestCompletionRecorded(
            user, campaignId, reputation.questCount, reputation.campaignCount
        );
    }

    function verifyChannel(address user, uint32 channelScore) external onlyRole(OPERATOR_ROLE) {
        if (user == address(0)) revert InvalidAddress();
        if (channelScore > 100) revert ScoreOutOfRange();
        _mintIfNeeded(user);

        Reputation storage reputation = reputations[user];
        reputation.isChannelVerified = true;
        reputation.channelScore = channelScore;
        reputation.lastUpdated = uint64(block.timestamp);

        emit ChannelVerified(user, channelScore);
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address previousOwner)
    {
        previousOwner = _ownerOf(tokenId);
        if (previousOwner != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function _mintIfNeeded(address user) private {
        if (tokenIds[user] != 0) return;
        uint256 tokenId = _nextTokenId++;
        tokenIds[user] = tokenId;
        _safeMint(user, tokenId);
        emit ReputationMinted(user, tokenId);
    }
}
