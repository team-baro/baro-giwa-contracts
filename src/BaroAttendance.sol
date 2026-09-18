// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/// @title BaroAttendance
/// @notice Wallet-bound EAS attendance approved by each session's authorized organizer.
contract BaroAttendance is AccessControlDefaultAdminRules {
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");

    struct Session {
        address organizer;
        uint64 start;
        uint64 end;
        uint8 kind;
        bytes32 metadataHash;
    }
    error InvalidConfiguration();
    mapping(uint256 sessionId => Session session) public sessions;

    constructor(address admin, address organizer) AccessControlDefaultAdminRules(1 days, admin) {
        if (organizer == address(0)) revert InvalidConfiguration();
        _grantRole(ORGANIZER_ROLE, organizer);
    }
}
