// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IBaroReputationSBT } from "./interfaces/IBaroReputationSBT.sol";

contract BaroCampaignEscrow is AccessControl, EIP712, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant QUEST_CLAIM_TYPEHASH = keccak256(
        "QuestClaim(address user,uint256 campaignId,uint256 questId,address rewardToken,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    struct Campaign {
        address projectOwner;
        address rewardToken;
        uint128 totalBudget;
        uint128 remainingBudget;
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
    error NativeTransferFailed();

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed projectOwner,
        address indexed rewardToken,
        uint256 totalBudget,
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

    IBaroReputationSBT public immutable REPUTATION_SBT;
    uint256 public nextCampaignId = 1;

    mapping(uint256 campaignId => Campaign campaign) public campaigns;
    mapping(address user => mapping(uint256 nonce => bool used)) public usedNonces;
    mapping(
        uint256 campaignId => mapping(uint256 questId => mapping(address user => bool claimed))
    ) public claimedQuests;

    constructor(address admin, address operator, IBaroReputationSBT reputationSbt_)
        EIP712("BaroCampaignEscrow", "1")
    {
        if (admin == address(0) || operator == address(0) || address(reputationSbt_) == address(0))
        {
            revert InvalidAddress();
        }
        REPUTATION_SBT = reputationSbt_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(PAUSER_ROLE, admin);
    }

    function createCampaign(
        address rewardToken,
        uint128 totalBudget,
        uint64 startTime,
        uint64 endTime
    ) external payable whenNotPaused returns (uint256 campaignId) {
        if (totalBudget == 0) revert InvalidBudget();
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
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });

        emit CampaignCreated(campaignId, msg.sender, rewardToken, totalBudget, startTime, endTime);
    }

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
        if (campaign.remainingBudget < claim.amount) revert InsufficientCampaignBudget();

        bytes32 digest = hashQuestClaim(claim);
        if (!hasRole(OPERATOR_ROLE, signer) || ECDSA.recover(digest, signature) != signer) {
            revert InvalidClaimSigner();
        }

        usedNonces[claim.user][claim.nonce] = true;
        claimedQuests[claim.campaignId][claim.questId][claim.user] = true;
        campaign.remainingBudget -= uint128(claim.amount);

        if (campaign.rewardToken == address(0)) {
            (bool sent,) = payable(claim.user).call{ value: claim.amount }("");
            if (!sent) revert NativeTransferFailed();
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

    function withdrawRemainingBudget(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.projectOwner) revert NotCampaignOwner();
        if (block.timestamp <= campaign.endTime) revert CampaignNotEnded();

        uint256 amount = campaign.remainingBudget;
        if (amount == 0) revert InvalidBudget();
        campaign.remainingBudget = 0;
        campaign.isActive = false;

        if (campaign.rewardToken == address(0)) {
            (bool sent,) = payable(campaign.projectOwner).call{ value: amount }("");
            if (!sent) revert NativeTransferFailed();
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
