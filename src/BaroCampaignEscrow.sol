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

/// @title BaroCampaignEscrow
/// @notice Holds a project's campaign budget and releases it to users who present an
///         operator-signed proof that they completed a quest.
/// @dev Payout authority is deliberately split so no single key can drain the escrow:
///      - `CAMPAIGN_CREATOR_ROLE` funds a campaign and fixes its budget and time window.
///      - `OPERATOR_ROLE` signs EIP-712 claims off-chain; the signature is checked on-chain.
///      - The user submits their own claim, so the escrow never pushes funds unprompted.
///
///      Reward accounting is tracked per token in {totalLiability}, which lets
///      {recoverExcessBalance} tell stray transfers apart from money owed to users.
contract BaroCampaignEscrow is AccessControlDefaultAdminRules, EIP712, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Signs quest claims off-chain and controls campaign lifecycle flags.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice May halt claims and campaign creation in an emergency.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice May fund new campaigns. Granted by {OPERATOR_ROLE} rather than the admin.
    bytes32 public constant CAMPAIGN_CREATOR_ROLE = keccak256("CAMPAIGN_CREATOR_ROLE");

    /// @notice Maintains the ERC-20 reward token allowlist.
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reputation points credited to the SBT for each completed quest.
    uint32 public constant QUEST_COMPLETION_POINTS = 10;

    /// @notice Timelock between scheduling and executing a reputation SBT swap.
    uint64 public constant REPUTATION_UPDATE_DELAY = 1 days;

    /// @notice EIP-712 struct hash for {QuestClaim}. Must stay byte-identical to the
    ///         type string the off-chain signer uses, or every signature fails to verify.
    bytes32 public constant QUEST_CLAIM_TYPEHASH = keccak256(
        "QuestClaim(address user,uint256 campaignId,uint256 questId,address rewardToken,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A funded reward pool with a fixed budget and time window.
    /// @dev Field order is chosen for storage packing: the four `uint128` amounts fill two
    ///      slots, and the two `uint64` timestamps plus `isActive` share a third.
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

    /// @notice The payload an operator signs to authorise a single reward payout.
    /// @dev Field order must match {QUEST_CLAIM_TYPEHASH} exactly.
    struct QuestClaim {
        address user;
        uint256 campaignId;
        uint256 questId;
        address rewardToken;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    // Setup and configuration.
    error InvalidAddress();
    error InvalidCampaignPeriod();
    error InvalidBudget();
    error NativeValueMismatch();
    error UnsupportedTokenBehavior();
    error UnsupportedRewardToken();

    // Campaign lookup and lifecycle state.
    error CampaignNotFound();
    error CampaignInactive();
    error CampaignNotStarted();
    error CampaignEnded();
    error CampaignNotEnded();
    error NotCampaignOwner();

    // Claim validation.
    error ClaimRecipientMismatch();
    error ClaimExpired();
    error ClaimDeadlineAfterCampaign();
    error ClaimConfigurationMismatch();
    error NonceAlreadyUsed();
    error QuestAlreadyClaimed();
    error InvalidClaimSigner();

    // Budget limits.
    error InsufficientCampaignBudget();
    error RewardExceedsMaximum();
    error UserRewardLimitExceeded();

    // Withdrawal and administration.
    error CampaignStillActive();
    error CampaignOwnerCancelled();
    error NoPendingReputationUpdate();
    error ReputationUpdateNotReady();
    error ExcessBalanceExceeded();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // Campaign lifecycle.
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

    // Fund movement.
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
    event ExcessBalanceRecovered(address indexed token, address indexed recipient, uint256 amount);

    // Reputation SBT bookkeeping.
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

    // Configuration.
    event RewardTokenSupportUpdated(address indexed rewardToken, bool isSupported);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    // NOTE: declaration order below is the contract's storage layout. Do not reorder.

    /// @notice Reputation SBT credited whenever a quest is claimed.
    IBaroReputationSBT public reputationSbt;

    /// @notice SBT queued by {scheduleReputationSbtUpdate}, zero when nothing is pending.
    address public pendingReputationSbt;

    /// @notice Timestamp after which {executeReputationSbtUpdate} may run.
    uint64 public reputationSbtUpdateAfter;

    /// @notice Auto-incrementing campaign id. Starts at 1 so 0 stays a "not found" sentinel.
    uint256 public nextCampaignId = 1;

    /// @notice Campaign configuration and live budget, keyed by campaign id.
    mapping(uint256 campaignId => Campaign campaign) public campaigns;

    /// @notice Campaigns the project owner cancelled. An operator may not reactivate these.
    mapping(uint256 campaignId => bool cancelled) public campaignOwnerCancelled;

    /// @notice Spent claim nonces per user, preventing signature replay.
    mapping(address user => mapping(uint256 nonce => bool used)) public usedNonces;

    /// @notice Quests already paid out, so a fresh nonce cannot double-claim the same quest.
    mapping(
        uint256 campaignId => mapping(uint256 questId => mapping(address user => bool claimed))
    ) public claimedQuests;

    /// @notice Running total paid to each user per campaign, checked against `maxRewardPerUser`.
    mapping(uint256 campaignId => mapping(address user => uint128 rewarded)) public userRewards;

    /// @notice Total amount per token still owed to campaigns. Any balance above this is excess.
    mapping(address rewardToken => uint256 liability) public totalLiability;

    /// @notice ERC-20 allowlist. The zero address (native GIWA) is enabled in the constructor.
    mapping(address rewardToken => bool supported) public supportedRewardTokens;

    /// @notice Quests paid out whose SBT update reverted, awaiting {retryReputationUpdate}.
    mapping(
        uint256 campaignId => mapping(uint256 questId => mapping(address user => bool pending))
    ) public pendingReputationUpdates;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param admin Default admin, subject to the 1 day {AccessControlDefaultAdminRules} delay.
    /// @param operator Address that signs quest claims and manages campaign state.
    /// @param reputationSbt_ Reputation SBT to credit on every successful claim.
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

        // Campaign creators are onboarded by the operator, not the admin, so day-to-day
        // onboarding does not need the timelocked admin key.
        _setRoleAdmin(CAMPAIGN_CREATOR_ROLE, OPERATOR_ROLE);

        // Native GIWA is always an allowed reward token.
        supportedRewardTokens[address(0)] = true;
    }

    /*//////////////////////////////////////////////////////////////
                           CAMPAIGN LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a campaign and takes custody of its full budget up front.
    /// @dev Pass `rewardToken == address(0)` and send exactly `totalBudget` as `msg.value`
    ///      to fund with native GIWA; otherwise send no value and pre-approve the ERC-20.
    /// @param rewardToken Reward token, or the zero address for native GIWA.
    /// @param totalBudget Total budget escrowed for this campaign.
    /// @param maxRewardPerClaim Ceiling for a single claim.
    /// @param maxRewardPerUser Lifetime ceiling per user within this campaign.
    /// @param startTime Timestamp from which claims are accepted.
    /// @param endTime Timestamp after which claims stop and withdrawal unlocks.
    /// @return campaignId Id assigned to the new campaign.
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
        // Checks: the per-claim ceiling must fit inside the per-user ceiling, which in
        // turn must fit inside the total budget.
        if (
            totalBudget == 0 || maxRewardPerClaim == 0 || maxRewardPerClaim > maxRewardPerUser
                || maxRewardPerUser > totalBudget
        ) {
            revert InvalidBudget();
        }
        if (startTime >= endTime || endTime <= block.timestamp) revert InvalidCampaignPeriod();

        // Interactions: pull the budget in before any state is written.
        if (rewardToken == address(0)) {
            if (msg.value != totalBudget) revert NativeValueMismatch();
        } else {
            if (!supportedRewardTokens[rewardToken]) revert UnsupportedRewardToken();
            if (msg.value != 0) revert NativeValueMismatch();

            // Compare balances around the transfer so fee-on-transfer and rebasing tokens,
            // whose accounting this contract cannot track, are rejected at funding time.
            IERC20 token = IERC20(rewardToken);
            uint256 balanceBefore = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), totalBudget);
            if (token.balanceOf(address(this)) - balanceBefore != totalBudget) {
                revert UnsupportedTokenBehavior();
            }
        }

        // Effects.
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

    /// @notice Enables or disables claims for a campaign.
    /// @dev A campaign the project owner cancelled cannot be reactivated by an operator.
    /// @param campaignId Campaign to update.
    /// @param isActive New active flag.
    function setCampaignActive(uint256 campaignId, bool isActive) external onlyRole(OPERATOR_ROLE) {
        Campaign storage campaign = _getCampaign(campaignId);
        if (isActive && campaignOwnerCancelled[campaignId]) revert CampaignOwnerCancelled();

        campaign.isActive = isActive;

        emit CampaignStatusChanged(campaignId, isActive);
    }

    /// @notice Stops claims for a campaign. Callable by the project owner or an operator.
    /// @dev When the project owner calls this the campaign is marked permanently cancelled,
    ///      which blocks any later operator reactivation.
    /// @param campaignId Campaign to deactivate.
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

    /*//////////////////////////////////////////////////////////////
                                 CLAIMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pays out a quest reward against an operator-signed claim.
    /// @dev The caller must be `claim.user`, so an operator signature alone cannot move funds
    ///      to a third party. Follows checks-effects-interactions: every guard and state write
    ///      happens before the transfer.
    /// @param claim Signed claim payload.
    /// @param signer Address that produced `signature`; must hold {OPERATOR_ROLE}.
    /// @param signature EIP-712 signature over `claim`. EIP-1271 wallets are supported.
    // Validation is kept together so every payout crosses the complete claim policy.
    // slither-disable-next-line cyclomatic-complexity,timestamp
    function claimReward(QuestClaim calldata claim, address signer, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
    {
        // Checks: the claim envelope itself.
        if (claim.user != msg.sender) revert ClaimRecipientMismatch();
        if (claim.amount == 0) revert InvalidBudget();
        if (block.timestamp > claim.deadline) revert ClaimExpired();
        if (usedNonces[claim.user][claim.nonce]) revert NonceAlreadyUsed();
        if (claimedQuests[claim.campaignId][claim.questId][claim.user]) {
            revert QuestAlreadyClaimed();
        }

        // Checks: campaign is live and the claim matches how it was configured.
        Campaign storage campaign = _getCampaign(claim.campaignId);
        if (!campaign.isActive) revert CampaignInactive();
        if (block.timestamp < campaign.startTime) revert CampaignNotStarted();
        if (block.timestamp > campaign.endTime) revert CampaignEnded();
        if (claim.deadline > campaign.endTime) revert ClaimDeadlineAfterCampaign();
        if (claim.rewardToken != campaign.rewardToken) revert ClaimConfigurationMismatch();

        // Checks: per-claim, per-user, and remaining-budget ceilings.
        if (claim.amount > campaign.maxRewardPerClaim) revert RewardExceedsMaximum();
        uint256 rewardedAfterClaim = userRewards[claim.campaignId][claim.user] + claim.amount;
        if (rewardedAfterClaim > campaign.maxRewardPerUser) revert UserRewardLimitExceeded();
        if (campaign.remainingBudget < claim.amount) revert InsufficientCampaignBudget();

        // Checks: the signature is valid and came from a current operator. Both conditions
        // are required, so revoking the role immediately invalidates unspent signatures.
        bytes32 digest = hashQuestClaim(claim);
        if (
            !hasRole(OPERATOR_ROLE, signer)
                || !SignatureChecker.isValidSignatureNow(signer, digest, signature)
        ) {
            revert InvalidClaimSigner();
        }

        // Effects: burn the nonce and the quest slot, then debit both budget and liability.
        usedNonces[claim.user][claim.nonce] = true;
        claimedQuests[claim.campaignId][claim.questId][claim.user] = true;
        campaign.remainingBudget -= uint128(claim.amount);
        userRewards[claim.campaignId][claim.user] = rewardedAfterClaim.toUint128();
        totalLiability[campaign.rewardToken] -= claim.amount;

        // Interactions: pay the user.
        if (campaign.rewardToken == address(0)) {
            payable(claim.user).sendValue(claim.amount);
        } else {
            IERC20(campaign.rewardToken).safeTransfer(claim.user, claim.amount);
        }

        // Interactions: credit reputation. A failing SBT must never block a payout the user
        // has already earned, so the failure is recorded for {retryReputationUpdate} instead.
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

    /// @notice Recomputes the EIP-712 digest for a claim.
    /// @dev Exposed so the off-chain signer and integrators can verify what they are signing.
    /// @param claim Claim payload to hash.
    /// @return EIP-712 digest bound to this contract and chain.
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

    /*//////////////////////////////////////////////////////////////
                               WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a finished campaign's unclaimed budget to its project owner.
    /// @dev Requires the campaign to be both past `endTime` and inactive, so an owner cannot
    ///      pull funds out from under claims that are still live.
    /// @param campaignId Campaign to withdraw from.
    // Campaign maturity intentionally uses the configured end timestamp.
    // slither-disable-next-line timestamp
    function withdrawRemainingBudget(uint256 campaignId) external nonReentrant {
        // Checks.
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.projectOwner) revert NotCampaignOwner();
        if (block.timestamp <= campaign.endTime) revert CampaignNotEnded();
        if (campaign.isActive) revert CampaignStillActive();

        uint256 amount = campaign.remainingBudget;
        if (amount == 0) revert InvalidBudget();

        // Effects.
        campaign.remainingBudget = 0;
        campaign.isActive = false;
        totalLiability[campaign.rewardToken] -= amount;

        // Interactions.
        if (campaign.rewardToken == address(0)) {
            payable(campaign.projectOwner).sendValue(amount);
        } else {
            IERC20(campaign.rewardToken).safeTransfer(campaign.projectOwner, amount);
        }

        emit RemainingBudgetWithdrawn(
            campaignId, campaign.projectOwner, campaign.rewardToken, amount
        );
    }

    /// @notice Sweeps tokens held beyond what campaigns still owe.
    /// @dev Withdrawal is capped at `balance - totalLiability`, so funds backing live
    ///      campaigns can never be swept. Covers direct transfers sent to this contract.
    /// @param rewardToken Token to sweep, or the zero address for native GIWA.
    /// @param recipient Address receiving the excess.
    /// @param amount Amount to sweep.
    function recoverExcessBalance(address rewardToken, address payable recipient, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        // Checks.
        if (recipient == address(0)) revert InvalidAddress();

        uint256 balance = rewardToken == address(0)
            ? address(this).balance
            : IERC20(rewardToken).balanceOf(address(this));
        uint256 liability = totalLiability[rewardToken];
        if (balance < liability || amount > balance - liability) revert ExcessBalanceExceeded();

        // Interactions.
        if (rewardToken == address(0)) {
            recipient.sendValue(amount);
        } else {
            IERC20(rewardToken).safeTransfer(recipient, amount);
        }

        emit ExcessBalanceRecovered(rewardToken, recipient, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            REPUTATION SBT
    //////////////////////////////////////////////////////////////*/

    /// @notice Replays an SBT update that failed during {claimReward}.
    /// @dev Permissionless: the pending marker is set by the contract itself, so anyone may
    ///      settle it. The marker is cleared before the external call.
    /// @param user User whose completion is pending.
    /// @param campaignId Campaign the quest belongs to.
    /// @param questId Quest to record.
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

    /// @notice Queues a replacement reputation SBT behind a {REPUTATION_UPDATE_DELAY} timelock.
    /// @dev Two-step by design: the delay gives users time to observe a pending migration
    ///      before the escrow starts writing to a different contract.
    /// @param reputationSbt_ SBT to migrate to.
    function scheduleReputationSbtUpdate(IBaroReputationSBT reputationSbt_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (address(reputationSbt_) == address(0)) revert InvalidAddress();

        pendingReputationSbt = address(reputationSbt_);
        reputationSbtUpdateAfter = uint64(block.timestamp) + REPUTATION_UPDATE_DELAY;

        emit ReputationSBTUpdateScheduled(pendingReputationSbt, reputationSbtUpdateAfter);
    }

    /// @notice Applies a scheduled SBT migration once its timelock has elapsed.
    // The timestamp enforces the disclosed SBT migration delay.
    // slither-disable-next-line timestamp
    function executeReputationSbtUpdate() external onlyRole(DEFAULT_ADMIN_ROLE) {
        address nextReputationSbt = pendingReputationSbt;
        if (nextReputationSbt == address(0) || block.timestamp < reputationSbtUpdateAfter) {
            revert ReputationUpdateNotReady();
        }

        address previousReputationSbt = address(reputationSbt);
        reputationSbt = IBaroReputationSBT(nextReputationSbt);

        // Clear the queue so the same migration cannot be replayed.
        pendingReputationSbt = address(0);
        reputationSbtUpdateAfter = 0;

        emit ReputationSBTUpdated(previousReputationSbt, nextReputationSbt);
    }

    /*//////////////////////////////////////////////////////////////
                             ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds or removes an ERC-20 from the reward token allowlist.
    /// @dev Native GIWA (the zero address) cannot be disabled.
    /// @param rewardToken Token to update.
    /// @param isSupported Whether new campaigns may be funded with it.
    function setRewardTokenSupported(address rewardToken, bool isSupported)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
    {
        if (rewardToken == address(0) && !isSupported) revert UnsupportedRewardToken();

        supportedRewardTokens[rewardToken] = isSupported;

        emit RewardTokenSupportUpdated(rewardToken, isSupported);
    }

    /// @notice Halts campaign creation and claims.
    /// @dev Withdrawals stay open so a pause cannot trap a project owner's funds.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes campaign creation and claims.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Loads a campaign and reverts if it was never created. `projectOwner` is the
    ///      existence sentinel because {createCampaign} always sets it to a non-zero address.
    function _getCampaign(uint256 campaignId) private view returns (Campaign storage campaign) {
        campaign = campaigns[campaignId];
        if (campaign.projectOwner == address(0)) revert CampaignNotFound();
    }
}
