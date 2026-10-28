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
}
