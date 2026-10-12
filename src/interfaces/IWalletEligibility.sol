// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Current wallet eligibility; consumers must reject false or failed reads.
interface IWalletEligibility {
    function isEligible(address user) external view returns (bool);
}

/// @notice ABI subset of the official DojangScroll verified-address reader.
interface IDojangScroll {
    function isVerified(address user, bytes32 attesterId) external view returns (bool);
    function getVerifiedAddressAttestationUid(address user, bytes32 attesterId)
        external
        view
        returns (bytes32);
}
