// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IBaroReputationSBT } from "./interfaces/IBaroReputationSBT.sol";

contract BaroCampaignEscrow is AccessControlDefaultAdminRules, EIP712, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CAMPAIGN_CREATOR_ROLE = keccak256("CAMPAIGN_CREATOR_ROLE");
    bytes32 public constant QUEST_CLAIM_TYPEHASH = keccak256(
        "QuestClaim(address user,uint256 campaignId,uint256 questId,address rewardToken,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    struct Campaign {
        address projectOwner;
        address rewardToken;
        uint128 totalBudget;
        uint128 remainingBudget;
        uint128 maxRewardPerClaim;
        uint64 startTime;
        uint64 endTime;
        bool isActive;
    }

    struct QuestClaim {
        address user;
        uint256 campaignId;
        uint256 questId;
        address rewardToken;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    error InvalidAddress();
    error InvalidCampaignPeriod();
    error InvalidBudget();
    error NativeValueMismatch();
    error UnsupportedTokenBehavior();
    error CampaignNotFound();
    error CampaignInactive();
    error CampaignNotStarted();
    error CampaignEnded();
    error CampaignNotEnded();
    error NotCampaignOwner();
    error ClaimRecipientMismatch();
    error ClaimExpired();
    error ClaimDeadlineAfterCampaign();
    error ClaimConfigurationMismatch();
    error NonceAlreadyUsed();
    error QuestAlreadyClaimed();
    error InvalidClaimSigner();
    error InsufficientCampaignBudget();
    error RewardExceedsMaximum();

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed projectOwner,
        address indexed rewardToken,
        uint256 totalBudget,
        uint256 maxRewardPerClaim,
        uint64 startTime,
        uint64 endTime
    );
    event CampaignStatusChanged(uint256 indexed campaignId, bool isActive);
    event RewardClaimed(
        uint256 indexed campaignId,
        uint256 indexed questId,
        address indexed user,
        address rewardToken,
        uint256 amount,
        uint256 nonce
    );
    event RemainingBudgetWithdrawn(
        uint256 indexed campaignId,
        address indexed projectOwner,
        address rewardToken,
        uint256 amount
    );

    // Immutable constants use Solidity's conventional upper-snake naming.
    // slither-disable-next-line naming-convention
    IBaroReputationSBT public immutable REPUTATION_SBT;
    uint256 public nextCampaignId = 1;

    mapping(uint256 campaignId => Campaign campaign) public campaigns;
    mapping(address user => mapping(uint256 nonce => bool used)) public usedNonces;
    mapping(
        uint256 campaignId => mapping(uint256 questId => mapping(address user => bool claimed))
    ) public claimedQuests;

    constructor(address admin, address operator, IBaroReputationSBT reputationSbt_)
        AccessControlDefaultAdminRules(1 days, admin)
        EIP712("BaroCampaignEscrow", "1")
    {
        if (admin == address(0) || operator == address(0) || address(reputationSbt_) == address(0))
        {
            revert InvalidAddress();
        }
        REPUTATION_SBT = reputationSbt_;
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(PAUSER_ROLE, admin);
        _setRoleAdmin(CAMPAIGN_CREATOR_ROLE, OPERATOR_ROLE);
    }

    // Campaign windows intentionally use miner-provided block timestamps.
    // slither-disable-next-line timestamp
    function createCampaign(
        address rewardToken,
        uint128 totalBudget,
        uint128 maxRewardPerClaim,
        uint64 startTime,
        uint64 endTime
    ) external payable onlyRole(CAMPAIGN_CREATOR_ROLE) whenNotPaused returns (uint256 campaignId) {
        if (totalBudget == 0 || maxRewardPerClaim == 0 || maxRewardPerClaim > totalBudget) {
            revert InvalidBudget();
        }
        if (startTime >= endTime || endTime <= block.timestamp) revert InvalidCampaignPeriod();

        if (rewardToken == address(0)) {
            if (msg.value != totalBudget) revert NativeValueMismatch();
        } else {
            if (msg.value != 0) revert NativeValueMismatch();
            IERC20 token = IERC20(rewardToken);
            uint256 balanceBefore = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), totalBudget);
            if (token.balanceOf(address(this)) - balanceBefore != totalBudget) {
                revert UnsupportedTokenBehavior();
            }
        }

        campaignId = nextCampaignId++;
        campaigns[campaignId] = Campaign({
            projectOwner: msg.sender,
            rewardToken: rewardToken,
            totalBudget: totalBudget,
            remainingBudget: totalBudget,
            maxRewardPerClaim: maxRewardPerClaim,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });

        emit CampaignCreated(
            campaignId, msg.sender, rewardToken, totalBudget, maxRewardPerClaim, startTime, endTime
        );
    }

    // Validation is kept together so every payout crosses the complete claim policy.
    // slither-disable-next-line cyclomatic-complexity,timestamp
    function claimReward(QuestClaim calldata claim, address signer, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
    {
        if (claim.user != msg.sender) revert ClaimRecipientMismatch();
        if (claim.amount == 0) revert InvalidBudget();
        if (block.timestamp > claim.deadline) revert ClaimExpired();
        if (usedNonces[claim.user][claim.nonce]) revert NonceAlreadyUsed();
        if (claimedQuests[claim.campaignId][claim.questId][claim.user]) {
            revert QuestAlreadyClaimed();
        }

        Campaign storage campaign = _getCampaign(claim.campaignId);
        if (!campaign.isActive) revert CampaignInactive();
        if (block.timestamp < campaign.startTime) revert CampaignNotStarted();
        if (block.timestamp > campaign.endTime) revert CampaignEnded();
        if (claim.deadline > campaign.endTime) revert ClaimDeadlineAfterCampaign();
        if (claim.rewardToken != campaign.rewardToken) revert ClaimConfigurationMismatch();
        if (claim.amount > campaign.maxRewardPerClaim) revert RewardExceedsMaximum();
        if (campaign.remainingBudget < claim.amount) revert InsufficientCampaignBudget();

        bytes32 digest = hashQuestClaim(claim);
        if (!hasRole(OPERATOR_ROLE, signer) || ECDSA.recover(digest, signature) != signer) {
            revert InvalidClaimSigner();
        }

        usedNonces[claim.user][claim.nonce] = true;
        claimedQuests[claim.campaignId][claim.questId][claim.user] = true;
        campaign.remainingBudget -= uint128(claim.amount);

        if (campaign.rewardToken == address(0)) {
            payable(claim.user).sendValue(claim.amount);
        } else {
            IERC20(campaign.rewardToken).safeTransfer(claim.user, claim.amount);
        }

        REPUTATION_SBT.recordQuestCompletion(claim.user, claim.campaignId);

        emit RewardClaimed(
            claim.campaignId,
            claim.questId,
            claim.user,
            claim.rewardToken,
            claim.amount,
            claim.nonce
        );
    }

    function setCampaignActive(uint256 campaignId, bool isActive) external onlyRole(OPERATOR_ROLE) {
        Campaign storage campaign = _getCampaign(campaignId);
        campaign.isActive = isActive;
        emit CampaignStatusChanged(campaignId, isActive);
    }

    // Campaign maturity intentionally uses the configured end timestamp.
    // slither-disable-next-line timestamp
    function withdrawRemainingBudget(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.projectOwner) revert NotCampaignOwner();
        if (block.timestamp <= campaign.endTime) revert CampaignNotEnded();

        uint256 amount = campaign.remainingBudget;
        if (amount == 0) revert InvalidBudget();
        campaign.remainingBudget = 0;
        campaign.isActive = false;

        if (campaign.rewardToken == address(0)) {
            payable(campaign.projectOwner).sendValue(amount);
        } else {
            IERC20(campaign.rewardToken).safeTransfer(campaign.projectOwner, amount);
        }

        emit RemainingBudgetWithdrawn(
            campaignId, campaign.projectOwner, campaign.rewardToken, amount
        );
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function hashQuestClaim(QuestClaim calldata claim) public view returns (bytes32) {
        // abi.encode is intentional here to mirror the canonical EIP-712 field encoding.
        bytes32 structHash = keccak256(
            abi.encode(
                QUEST_CLAIM_TYPEHASH,
                claim.user,
                claim.campaignId,
                claim.questId,
                claim.rewardToken,
                claim.amount,
                claim.nonce,
                claim.deadline
            )
        );
        return _hashTypedDataV4(structHash);
    }

    function _getCampaign(uint256 campaignId) private view returns (Campaign storage campaign) {
        campaign = campaigns[campaignId];
        if (campaign.projectOwner == address(0)) revert CampaignNotFound();
    }
}
