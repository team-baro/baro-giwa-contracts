// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { IBaroReputationSBT } from "./interfaces/IBaroReputationSBT.sol";

contract BaroReputationSBT is ERC721, AccessControlDefaultAdminRules, IBaroReputationSBT {
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
    event BaseURIUpdated(string baseURI);

    mapping(address user => Reputation reputation) public reputations;
    mapping(address user => uint256 tokenId) public tokenIds;
    mapping(address user => mapping(uint256 campaignId => bool participated)) public
        hasParticipatedInCampaign;

    uint256 private _nextTokenId = 1;
    string private _baseTokenUri;

    constructor(address admin, address operator, address escrow, string memory baseTokenURI)
        ERC721("Baro Reputation", "BARO-SBT")
        AccessControlDefaultAdminRules(1 days, admin)
    {
        if (admin == address(0) || operator == address(0) || escrow == address(0)) {
            revert InvalidAddress();
        }
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(ESCROW_ROLE, escrow);
        _baseTokenUri = baseTokenURI;
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

    function setBaseURI(string calldata baseTokenURI) external onlyRole(OPERATOR_ROLE) {
        _baseTokenUri = baseTokenURI;
        emit BaseURIUpdated(baseTokenURI);
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
        override(ERC721, AccessControlDefaultAdminRules)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenUri;
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
        _mint(user, tokenId);
        emit ReputationMinted(user, tokenId);
    }
}
