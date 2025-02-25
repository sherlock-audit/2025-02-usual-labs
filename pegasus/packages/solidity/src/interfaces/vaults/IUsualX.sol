// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IUsualX {
    function startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
        external;
    function sweepFees(address collector) external;
    function setBurnRatio(uint256 burnRatioBps) external;
    function getYieldRate() external view returns (uint256);
    function getBurnRatio() external view returns (uint256);
    function getAccumulatedFees() external view returns (uint256);
}
