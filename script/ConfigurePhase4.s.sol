// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Script } from "forge-std/Script.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";

/// @notice Separate admin-signed step; the deployer never receives admin authority implicitly.
contract ConfigurePhase4 is Script {
    function run() external {
        require(block.chainid == 91_342, "Wrong chain");
        address admin = vm.envAddress("BARO_ADMIN_ADDRESS");
        address creator = vm.envAddress("BARO_CAMPAIGN_CREATOR");
        require(creator != address(0), "Missing creator");
        BaroPerformanceEscrow escrow =
            BaroPerformanceEscrow(vm.envAddress("BARO_PERFORMANCE_ESCROW"));
        require(escrow.defaultAdmin() == admin, "Wrong admin");
        address token = vm.envOr("BARO_REWARD_TOKEN", address(0));
        vm.startBroadcast(admin);
        escrow.grantRole(escrow.CREATOR_ROLE(), creator);
        escrow.setRewardTokenSupported(token, true);
        vm.stopBroadcast();
    }
}
