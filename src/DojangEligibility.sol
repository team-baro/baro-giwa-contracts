// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { IEAS, Attestation } from "./interfaces/IEAS.sol";
import { IWalletEligibility, IDojangScroll } from "./interfaces/IWalletEligibility.sol";

/// @notice Fail-closed adapter for Dojang's Upbit Korea verified-address attestations.
/// @dev Immutable configuration is a trust boundary; deploy a new adapter to change it.
contract DojangEligibility is IWalletEligibility {
    bytes32 public constant UPBIT_KOREA_ID = keccak256("dojang.dojangattesterids.upbitkorea");
    IEAS public immutable EAS;
    IDojangScroll public immutable SCROLL;
    address public immutable ISSUER;
    bytes32 public immutable VERIFIED_ADDRESS_SCHEMA;
    error InvalidConfiguration();
    error OnlySelf();

    constructor(IEAS eas, IDojangScroll scroll, address issuer, bytes32 schema) {
        if (
            address(eas).code.length == 0 || address(scroll).code.length == 0
                || issuer == address(0) || schema == bytes32(0)
        ) revert InvalidConfiguration();
        EAS = eas;
        SCROLL = scroll;
        ISSUER = issuer;
        VERIFIED_ADDRESS_SCHEMA = schema;
    }

    /// @notice Return false for failed calls and malformed external ABI responses alike.
    function isEligible(address user) external view returns (bool) {
        // ABI decoding errors occur in the caller and escape a try around the dependency call.
        // An external self-call keeps all dependency reads/decoding inside the catchable frame.
        try this.readEligibility(user) returns (bool eligible) {
            return eligible;
        } catch {
            return false;
        }
    }

    /// @dev Internal-only external boundary so malformed return data cannot revert isEligible.
    function readEligibility(address user) external view returns (bool) {
        if (msg.sender != address(this)) revert OnlySelf();
        bytes32 uid = bytes32(0);
        try SCROLL.isVerified(user, UPBIT_KOREA_ID) returns (bool verified) {
            if (!verified) return false;
        } catch {
            return false;
        }
        try SCROLL.getVerifiedAddressAttestationUid(user, UPBIT_KOREA_ID) returns (
            bytes32 current
        ) {
            uid = current;
        } catch {
            return false;
        }
        if (uid == bytes32(0)) return false;
        try EAS.getAttestation(uid) returns (Attestation memory record) {
            if (user == address(0) || record.recipient != user) return false;
            if (
                record.time == 0 || record.time > block.timestamp || record.revocationTime != 0
                    || (record.expirationTime != 0 && record.expirationTime <= block.timestamp)
                    || record.data.length != 32
            ) return false;
            // Reject noncanonical ABI booleans without propagating a decode revert.
            uint256 verifiedWord = abi.decode(record.data, (uint256));
            if (verifiedWord != 1) return false;
            return record.uid == uid && record.schema == VERIFIED_ADDRESS_SCHEMA
                && record.attester == ISSUER;
        } catch {
            return false;
        }
    }
}
