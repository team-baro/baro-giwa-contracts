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

    function isEligible(address user) external view returns (bool) {
        bytes32 uid;
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
            return record.uid == uid && record.schema == VERIFIED_ADDRESS_SCHEMA
                && record.attester == ISSUER;
        } catch {
            return false;
        }
    }
}
