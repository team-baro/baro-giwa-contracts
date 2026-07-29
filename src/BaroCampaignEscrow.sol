// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IBaroReputationSBT } from "./interfaces/IBaroReputationSBT.sol";

contract BaroCampaignEscrow is AccessControlDefaultAdminRules, EIP712, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using SafeCast for uint256;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CAMPAIGN_CREATOR_ROLE = keccak256("CAMPAIGN_CREATOR_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    uint32 public constant QUEST_COMPLETION_POINTS = 10;
    uint64 public constant REPUTATION_UPDATE_DELAY = 1 days;
    bytes32 public constant QUEST_CLAIM_TYPEHASH = keccak256(
        "QuestClaim(address user,uint256 campaignId,uint256 questId,address rewardToken,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    struct Campaign {
        address projectOwner;
        address rewardToken;
        uint128 totalBudget;
        uint128 remainingBudget;
        uint128 maxRewardPerClaim;
        uint128 maxRewardPerUser;
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
    error UnsupportedRewardToken();
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
    error UserRewardLimitExceeded();
    error CampaignStillActive();
    error CampaignOwnerCancelled();
    error NoPendingReputationUpdate();
    error ReputationUpdateNotReady();
    error ExcessBalanceExceeded();

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed projectOwner,
        address indexed rewardToken,
        uint256 totalBudget,
        uint256 maxRewardPerClaim,
        uint256 maxRewardPerUser,
        uint64 startTime,
        uint64 endTime
    );
    event CampaignStatusChanged(uint256 indexed campaignId, bool isActive);
    event CampaignCancelled(uint256 indexed campaignId, address indexed projectOwner);
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
    event RewardTokenSupportUpdated(address indexed rewardToken, bool isSupported);
    event ReputationUpdateDeferred(
        address indexed user, uint256 indexed campaignId, uint256 indexed questId
    );
    event ReputationUpdateRetried(
        address indexed user, uint256 indexed campaignId, uint256 indexed questId
    );
    event ReputationSBTUpdateScheduled(address indexed reputationSbt, uint64 executeAfter);
    event ReputationSBTUpdated(
        address indexed previousReputationSbt, address indexed reputationSbt
    );
    event ExcessBalanceRecovered(address indexed token, address indexed recipient, uint256 amount);

    IBaroReputationSBT public reputationSbt;
    address public pendingReputationSbt;
    uint64 public reputationSbtUpdateAfter;
    uint256 public nextCampaignId = 1;

    mapping(uint256 campaignId => Campaign campaign) public campaigns;
    mapping(uint256 campaignId => bool cancelled) public campaignOwnerCancelled;
    mapping(address user => mapping(uint256 nonce => bool used)) public usedNonces;
    mapping(
        uint256 campaignId => mapping(uint256 questId => mapping(address user => bool claimed))
    ) public claimedQuests;
    mapping(uint256 campaignId => mapping(address user => uint128 rewarded)) public userRewards;
    mapping(address rewardToken => uint256 liability) public totalLiability;
    mapping(address rewardToken => bool supported) public supportedRewardTokens;
    mapping(
        uint256 campaignId => mapping(uint256 questId => mapping(address user => bool pending))
    ) public pendingReputationUpdates;

    constructor(address admin, address operator, IBaroReputationSBT reputationSbt_)
        AccessControlDefaultAdminRules(1 days, admin)
        EIP712("BaroCampaignEscrow", "1")
    {
        if (admin == address(0) || operator == address(0) || address(reputationSbt_) == address(0))
        {
            revert InvalidAddress();
        }
        reputationSbt = reputationSbt_;
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(TOKEN_MANAGER_ROLE, admin);
        _setRoleAdmin(CAMPAIGN_CREATOR_ROLE, OPERATOR_ROLE);
        supportedRewardTokens[address(0)] = true;
    }

    // Campaign windows intentionally use miner-provided block timestamps.
    // slither-disable-next-line timestamp
    function createCampaign(
        address rewardToken,
        uint128 totalBudget,
        uint128 maxRewardPerClaim,
        uint128 maxRewardPerUser,
        uint64 startTime,
        uint64 endTime
    )
        external
        payable
        onlyRole(CAMPAIGN_CREATOR_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 campaignId)
    {
        if (
            totalBudget == 0 || maxRewardPerClaim == 0 || maxRewardPerClaim > maxRewardPerUser
                || maxRewardPerUser > totalBudget
        ) {
            revert InvalidBudget();
        }
        if (startTime >= endTime || endTime <= block.timestamp) revert InvalidCampaignPeriod();

        if (rewardToken == address(0)) {
            if (msg.value != totalBudget) revert NativeValueMismatch();
        } else {
            if (!supportedRewardTokens[rewardToken]) revert UnsupportedRewardToken();
            if (msg.value != 0) revert NativeValueMismatch();
            IERC20 token = IERC20(rewardToken);
            uint256 balanceBefore = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), totalBudget);
            if (token.balanceOf(address(this)) - balanceBefore != totalBudget) {
                revert UnsupportedTokenBehavior();
            }
        }

        campaignId = nextCampaignId++;
        totalLiability[rewardToken] += totalBudget;
        campaigns[campaignId] = Campaign({
            projectOwner: msg.sender,
            rewardToken: rewardToken,
            totalBudget: totalBudget,
            remainingBudget: totalBudget,
            maxRewardPerClaim: maxRewardPerClaim,
            maxRewardPerUser: maxRewardPerUser,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });

        emit CampaignCreated(
            campaignId,
            msg.sender,
            rewardToken,
            totalBudget,
            maxRewardPerClaim,
            maxRewardPerUser,
            startTime,
            endTime
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
        uint256 rewardedAfterClaim = userRewards[claim.campaignId][claim.user] + claim.amount;
        if (rewardedAfterClaim > campaign.maxRewardPerUser) revert UserRewardLimitExceeded();
        if (campaign.remainingBudget < claim.amount) revert InsufficientCampaignBudget();

        bytes32 digest = hashQuestClaim(claim);
        if (
            !hasRole(OPERATOR_ROLE, signer)
                || !SignatureChecker.isValidSignatureNow(signer, digest, signature)
        ) {
            revert InvalidClaimSigner();
        }

        usedNonces[claim.user][claim.nonce] = true;
        claimedQuests[claim.campaignId][claim.questId][claim.user] = true;
        campaign.remainingBudget -= uint128(claim.amount);
        userRewards[claim.campaignId][claim.user] = rewardedAfterClaim.toUint128();
        totalLiability[campaign.rewardToken] -= claim.amount;

        if (campaign.rewardToken == address(0)) {
            payable(claim.user).sendValue(claim.amount);
        } else {
            IERC20(campaign.rewardToken).safeTransfer(claim.user, claim.amount);
        }

        // claimReward is nonReentrant; only the deferred-retry marker is written in the catch path.
        // slither-disable-next-line reentrancy-benign
        try reputationSbt.recordQuestCompletion(
            claim.user, claim.campaignId, claim.questId, QUEST_COMPLETION_POINTS
        ) { }
        catch {
            pendingReputationUpdates[claim.campaignId][claim.questId][claim.user] = true;
            emit ReputationUpdateDeferred(claim.user, claim.campaignId, claim.questId);
        }

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
        if (isActive && campaignOwnerCancelled[campaignId]) revert CampaignOwnerCancelled();
        campaign.isActive = isActive;
        emit CampaignStatusChanged(campaignId, isActive);
    }

    function deactivateCampaign(uint256 campaignId) external {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.projectOwner && !hasRole(OPERATOR_ROLE, msg.sender)) {
            revert NotCampaignOwner();
        }
        if (msg.sender == campaign.projectOwner) {
            campaignOwnerCancelled[campaignId] = true;
            emit CampaignCancelled(campaignId, campaign.projectOwner);
        }
        campaign.isActive = false;
        emit CampaignStatusChanged(campaignId, false);
    }

    // Campaign maturity intentionally uses the configured end timestamp.
    // slither-disable-next-line timestamp
    function withdrawRemainingBudget(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.projectOwner) revert NotCampaignOwner();
        if (block.timestamp <= campaign.endTime) revert CampaignNotEnded();
        if (campaign.isActive) revert CampaignStillActive();

        uint256 amount = campaign.remainingBudget;
        if (amount == 0) revert InvalidBudget();
        campaign.remainingBudget = 0;
        campaign.isActive = false;
        totalLiability[campaign.rewardToken] -= amount;

        if (campaign.rewardToken == address(0)) {
            payable(campaign.projectOwner).sendValue(amount);
        } else {
            IERC20(campaign.rewardToken).safeTransfer(campaign.projectOwner, amount);
        }

        emit RemainingBudgetWithdrawn(
            campaignId, campaign.projectOwner, campaign.rewardToken, amount
        );
    }

    function retryReputationUpdate(address user, uint256 campaignId, uint256 questId)
        external
        whenNotPaused
        nonReentrant
    {
        if (!pendingReputationUpdates[campaignId][questId][user]) {
            revert NoPendingReputationUpdate();
        }
        pendingReputationUpdates[campaignId][questId][user] = false;
        reputationSbt.recordQuestCompletion(user, campaignId, questId, QUEST_COMPLETION_POINTS);
        // The nonReentrant guard prevents event-order reentrancy around the external SBT call.
        // slither-disable-next-line reentrancy-events
        emit ReputationUpdateRetried(user, campaignId, questId);
    }

    function scheduleReputationSbtUpdate(IBaroReputationSBT reputationSbt_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (address(reputationSbt_) == address(0)) revert InvalidAddress();
        pendingReputationSbt = address(reputationSbt_);
        reputationSbtUpdateAfter = uint64(block.timestamp) + REPUTATION_UPDATE_DELAY;
        emit ReputationSBTUpdateScheduled(pendingReputationSbt, reputationSbtUpdateAfter);
    }

    // The timestamp enforces the disclosed SBT migration delay.
    // slither-disable-next-line timestamp
    function executeReputationSbtUpdate() external onlyRole(DEFAULT_ADMIN_ROLE) {
        address nextReputationSbt = pendingReputationSbt;
        if (nextReputationSbt == address(0) || block.timestamp < reputationSbtUpdateAfter) {
            revert ReputationUpdateNotReady();
        }
        address previousReputationSbt = address(reputationSbt);
        reputationSbt = IBaroReputationSBT(nextReputationSbt);
        pendingReputationSbt = address(0);
        reputationSbtUpdateAfter = 0;
        emit ReputationSBTUpdated(previousReputationSbt, nextReputationSbt);
    }

    function setRewardTokenSupported(address rewardToken, bool isSupported)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
    {
        if (rewardToken == address(0) && !isSupported) revert UnsupportedRewardToken();
        supportedRewardTokens[rewardToken] = isSupported;
        emit RewardTokenSupportUpdated(rewardToken, isSupported);
    }

    function recoverExcessBalance(address rewardToken, address payable recipient, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        if (recipient == address(0)) revert InvalidAddress();
        uint256 balance = rewardToken == address(0)
            ? address(this).balance
            : IERC20(rewardToken).balanceOf(address(this));
        uint256 liability = totalLiability[rewardToken];
        if (balance < liability || amount > balance - liability) revert ExcessBalanceExceeded();

        if (rewardToken == address(0)) {
            recipient.sendValue(amount);
        } else {
            IERC20(rewardToken).safeTransfer(recipient, amount);
        }
        emit ExcessBalanceRecovered(rewardToken, recipient, amount);
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
