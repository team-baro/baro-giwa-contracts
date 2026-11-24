// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { BaroAttendance } from "../src/BaroAttendance.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { IWalletEligibility } from "../src/interfaces/IWalletEligibility.sol";
import { MockEAS } from "./mocks/MockEAS.sol";

/// @dev Vectors signed independently by cast wallet sign --data, not by contract hash helpers.
contract TypedDataCompatibilityTest is Test {
    function testCastAttendanceTypedDataMatchesSolidity() public {
        vm.chainId(91342);
        MockEAS eas = new MockEAS();
        bytes32 schema = eas.registry()
            .register("uint256 sessionId,uint8 kind,bytes32 metadataHash", address(0), false);
        BaroAttendance original = new BaroAttendance(
            address(this), address(this), eas, schema, IWalletEligibility(address(0))
        );
        address target = 0x1111111111111111111111111111111111111111;
        vm.etch(target, address(original).code);
        bytes32 digest = BaroAttendance(target).hashClaim(1, address(0xCAFE), 1003700);
        assertEq(
            ECDSA.recover(
                digest,
                hex"af9d19a2a74ea93b7d8768c1391fcf918ae5ec2cd3d37ea3816bdd2c5039dab44004e416bc5900531eb193ffd4e020ebc40a7c86b44ed85ecdfbd860081956fa1c"
            ),
            vm.addr(0xB0B)
        );
    }

    function testCastPerformanceTypedDataMatchesSolidity() public {
        vm.chainId(91342);
        BaroPerformanceEscrow original = new BaroPerformanceEscrow(address(this), address(this));
        address target = 0x2222222222222222222222222222222222222222;
        vm.etch(target, address(original).code);
        BaroPerformanceEscrow.ActionReceipt memory receipt = BaroPerformanceEscrow.ActionReceipt({
            campaignId: 1,
            user: address(0xCAFE),
            channel: address(0x2222),
            evidenceHash: 0xabababababababababababababababababababababababababababababababab,
            actionAt: 1000100,
            deadline: 1003700
        });
        assertEq(
            ECDSA.recover(
                BaroPerformanceEscrow(target).hashReceipt(receipt),
                hex"0b7c5ac2bca06ffe929116136e76a8cc0677626186376f70e208367243e4b5d17d46c585e6b95c0e60999475e0de1f0e38e7bae32011b530e3c4fd9762de04591b"
            ),
            vm.addr(0xB0B)
        );
    }
}
