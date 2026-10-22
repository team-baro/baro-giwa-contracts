// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { IWalletEligibility, IDojangScroll } from "../../src/interfaces/IWalletEligibility.sol";

contract MockEligibility is IWalletEligibility {
    mapping(address => bool) public eligible;
    bool public fail;

    function configure(address user, bool value, bool fails) external {
        eligible[user] = value;
        fail = fails;
    }

    function isEligible(address user) external view returns (bool) {
        require(!fail, "verifier unavailable");
        return eligible[user];
    }
}

contract MockDojangScroll is IDojangScroll {
    mapping(address => mapping(bytes32 => bytes32)) internal uids;
    bool public failVerified;
    bool public failUid;

    function set(address user, bytes32 attesterId, bytes32 uid) external {
        uids[user][attesterId] = uid;
    }

    function configure(bool first, bool second) external {
        failVerified = first;
        failUid = second;
    }

    function isVerified(address user, bytes32 attesterId) external view returns (bool) {
        require(!failVerified, "scroll unavailable");
        return uids[user][attesterId] != bytes32(0);
    }

    function getVerifiedAddressAttestationUid(address user, bytes32 attesterId)
        external
        view
        returns (bytes32)
    {
        require(!failUid, "UID unavailable");
        return uids[user][attesterId];
    }
}
