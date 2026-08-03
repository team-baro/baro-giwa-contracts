// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { BaroQuestTestToken } from "../src/BaroQuestTestToken.sol";

contract BaroQuestTestTokenTest is Test {
    address private recipient = makeAddr("recipient");

    function testMintsFixedSupplyToConfiguredRecipient() external {
        BaroQuestTestToken token = new BaroQuestTestToken(recipient, 25_000 ether);

        assertEq(token.name(), "Baro Quest Test Token");
        assertEq(token.symbol(), "BQT");
        assertEq(token.totalSupply(), 25_000 ether);
        assertEq(token.balanceOf(recipient), 25_000 ether);
    }

    function testRejectsInvalidDeploymentConfiguration() external {
        vm.expectRevert(BaroQuestTestToken.InvalidRecipient.selector);
        new BaroQuestTestToken(address(0), 1 ether);

        vm.expectRevert(BaroQuestTestToken.InvalidSupply.selector);
        new BaroQuestTestToken(recipient, 0);
    }
}
