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

    event SessionCreated(
        uint256 indexed sessionId,
        address indexed organizer,
        uint64 start,
        uint64 end,
        uint8 kind,
        bytes32 metadataHash
    );

    /// @notice Create immutable talk (0) or quest (1) terms before the session starts.
    function createSession(
        uint256 sessionId,
        uint64 start,
        uint64 end,
        uint8 kind,
        bytes32 metadataHash
    ) external onlyRole(ORGANIZER_ROLE) {
        _createSession(sessionId, start, end, kind, metadataHash);
    }

    function _createSession(
        uint256 sessionId,
        uint64 start,
        uint64 end,
        uint8 kind,
        bytes32 metadataHash
    ) internal {
        if (
            sessionId == 0 || sessions[sessionId].organizer != address(0) || start < block.timestamp
                || end <= start || kind > 1 || metadataHash == bytes32(0)
        ) revert InvalidConfiguration();
        sessions[sessionId] = Session({
            organizer: msg.sender, start: start, end: end, kind: kind, metadataHash: metadataHash
        });
        emit SessionCreated(sessionId, msg.sender, start, end, kind, metadataHash);
    }
}
