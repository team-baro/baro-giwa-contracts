// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { IWalletEligibility } from "./interfaces/IWalletEligibility.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/// @title BaroPerformanceEscrow
/// @notice Fixed channel payouts against campaign-scoped verifier approvals of user actions.
/// @dev The verifier is trusted to confirm offchain action evidence. No arbitrary admin withdrawal exists.
contract BaroPerformanceEscrow is
    AccessControlDefaultAdminRules,
    EIP712,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;
    using Address for address payable;
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    error InvalidConfiguration();
    error InvalidCampaign();

    constructor(address admin, address verifier)
        AccessControlDefaultAdminRules(1 days, admin)
        EIP712("BaroPerformanceEscrow", "1")
    {
        if (verifier == address(0)) {
            revert InvalidConfiguration();
        }
        _grantRole(VERIFIER_ROLE, verifier);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    struct Terms {
        address channel;
        address token;
        address verifier;
        IWalletEligibility eligibility;
        uint128 budget;
        uint128 unitReward;
        uint64 start;
        uint64 end;
        bytes32 conditionHash;
    }

    struct Campaign {
        address owner;
        Terms terms;
        uint256 remainingBudget;
        uint256 paidBudget;
    }
    mapping(uint256 campaignId => Campaign) private _campaigns;
    uint256 public campaignCount;
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed owner,
        address indexed channel,
        bytes32 conditionHash
    );

    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        return _campaign(campaignId);
    }

    function _campaign(uint256 campaignId) internal view returns (Campaign storage campaign) {
        campaign = _campaigns[campaignId];
        if (campaign.owner == address(0)) revert InvalidCampaign();
    }

    function _validateTerms(Terms calldata terms) internal view {
        if (
            terms.channel == address(0) || terms.channel == address(this)
                || !hasRole(VERIFIER_ROLE, terms.verifier) || terms.budget == 0
                || terms.unitReward == 0 || terms.unitReward > terms.budget
                || terms.start < block.timestamp || terms.end <= terms.start
                || terms.conditionHash == bytes32(0)
                || (address(terms.eligibility) != address(0)
                    && address(terms.eligibility).code.length == 0)
        ) revert InvalidConfiguration();
    }
}
