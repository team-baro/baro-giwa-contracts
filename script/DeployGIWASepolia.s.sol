// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";

import { BaroCampaignEscrow } from "../src/BaroCampaignEscrow.sol";
import { BaroReputationSBT } from "../src/BaroReputationSBT.sol";

contract DeployGIWASepolia is Script {
    function run() external returns (BaroCampaignEscrow escrow, BaroReputationSBT reputation) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("BARO_ADMIN_ADDRESS");
        address operator = vm.envAddress("BARO_OPERATOR_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        reputation = new BaroReputationSBT(deployer, operator);
        escrow = new BaroCampaignEscrow(admin, operator, reputation);
        reputation.grantRole(reputation.ESCROW_ROLE(), address(escrow));
        if (admin != deployer) {
            reputation.grantRole(reputation.DEFAULT_ADMIN_ROLE(), admin);
            reputation.renounceRole(reputation.DEFAULT_ADMIN_ROLE(), deployer);
        }
        vm.stopBroadcast();
    }
}
