// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {UsualS} from "src/token/UsualS.sol";

contract UsualSHarness is UsualS {
    // Function to mint new tokens
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Function to burn tokens
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
