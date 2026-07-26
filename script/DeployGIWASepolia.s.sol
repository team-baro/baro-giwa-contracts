// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";

import { BaroCampaignEscrow } from "../src/BaroCampaignEscrow.sol";
import { BaroReputationSBT } from "../src/BaroReputationSBT.sol";
import { IBaroReputationSBT } from "../src/interfaces/IBaroReputationSBT.sol";

contract DeployGIWASepolia is Script {
    function run() external returns (BaroCampaignEscrow escrow, BaroReputationSBT reputation) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("BARO_ADMIN_ADDRESS");
        address operator = vm.envAddress("BARO_OPERATOR_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);
        string memory baseTokenURI = vm.envOr("BARO_SBT_BASE_URI", string(""));
        address predictedReputation = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        vm.startBroadcast(deployerPrivateKey);
        escrow = new BaroCampaignEscrow(admin, operator, IBaroReputationSBT(predictedReputation));
        reputation = new BaroReputationSBT(admin, operator, address(escrow), baseTokenURI);
        vm.stopBroadcast();

        require(address(reputation) == predictedReputation, "Unexpected reputation address");
    }
}
