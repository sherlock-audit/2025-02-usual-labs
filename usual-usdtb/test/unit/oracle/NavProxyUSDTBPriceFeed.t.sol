// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test, console2 } from "../../../lib/forge-std/src/Test.sol";

import { MockPyth, MockNavOracle } from "../../utils/Mocks.sol";

import { NAVProxyUSDTBPriceFeed } from "../../../src/oracle/NAVProxyUSDTBPriceFeed.sol";

contract NAVProxyUSDTBPriceFeedUnitTests is Test {
    NAVProxyUSDTBPriceFeed public priceFeed;
    MockPyth public mockPyth;

    function setUp() public {
        mockPyth = new MockPyth();
        priceFeed = new NAVProxyUSDTBPriceFeed(address(mockPyth), bytes32(0));
    }

    function test_constructor() external view {
        assertEq(priceFeed.priceId(), bytes32(0));
        assertEq(priceFeed.version(), 1);
        assertEq(priceFeed.decimals(), 8);
    }

    function test_updateFeeds() external {
        mockPyth.setRoundData(1e10, block.timestamp);
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        assertEq(roundId, block.timestamp);
        assertEq(price, 1e8);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, block.timestamp);
    }

    function test_latestRoundData_belowThreshold() external {
        mockPyth.setRoundData(5e9, block.timestamp);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed
            .latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 5e7); // No threshold applied
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function test_latestRoundData_aboveThreshold() external {
        mockPyth.setRoundData(1.5e10, block.timestamp);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed
            .latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 1e8); // Threshold applied
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }
}
