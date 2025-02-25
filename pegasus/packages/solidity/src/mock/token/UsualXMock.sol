// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IUsualX} from "src/interfaces/vaults/IUsualX.sol";

contract UsualXMock is IUsualX {
    bool public wasStartYieldDistributionCalled;
    uint256 public calledWithYieldAmount;
    uint256 public calledWithStartTime;
    uint256 public calledWithEndTime;

    uint256 public calledWithBurnRatio;
    uint256 public calledWithYieldRate;
    uint256 public calledWithAccumulatedFees;
    address public calledWithCollector;

    function startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
        external
    {
        wasStartYieldDistributionCalled = true;
        calledWithYieldAmount = yieldAmount;
        calledWithStartTime = startTime;
        calledWithEndTime = endTime;
    }

    function setBurnRatio(uint256 burnRatioBps) external {
        calledWithBurnRatio = burnRatioBps;
    }

    function sweepFees(address collector) external {
        calledWithCollector = collector;
    }

    function getBurnRatio() external view returns (uint256) {
        return calledWithBurnRatio;
    }

    function getAccumulatedFees() external view returns (uint256) {
        return calledWithAccumulatedFees;
    }

    function getYieldRate() external view returns (uint256) {
        return calledWithYieldRate;
    }
}
