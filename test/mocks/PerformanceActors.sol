// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { MockERC20 } from "./MockERC20.sol";

contract TaxToken is MockERC20 {
    bool public tax;

    function setTax(bool enabled) external {
        tax = enabled;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (tax && from != address(0) && to != address(0) && amount > 0) {
            super._update(from, address(0), amount / 10);
            super._update(from, to, amount - amount / 10);
        } else {
            super._update(from, to, amount);
        }
    }
}

contract PerformanceReceiver {
    bool public reject;
    bool public callbackSucceeded;
    address public target;
    bytes public payload;

    function configure(bool rejects, address callback, bytes calldata data) external {
        reject = rejects;
        target = callback;
        payload = data;
    }

    receive() external payable {
        require(!reject, "reject ETH");
        if (target != address(0)) (callbackSucceeded,) = target.call(payload);
    }
}
