// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.26;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { NAV_POSITIVE_THRESHOLD, NAV_PRICE_DECIMALS } from "../constants.sol";
/**
 * @title  NAV Proxy USDTB Chainlink Compatible Price Feed
 * @notice A proxy contract that retrieves NAV (Net Asset Value) data from an external oracle,
 *         converts it to a USDTB price based on a specified threshold, and is compatible with
 *         the Chainlink AggregatorV3Interface.
 * @dev This contract is a modified version of the PythAggregatorV3 contract from the Pyth Network.
 * @author Pyth Labs
 * @author modified by Usual Labs
 */
contract NAVProxyUSDTBPriceFeed {

    /// @notice The Pyth price ID for the USDTB NAV.
    bytes32 public priceId;

    /// @notice The Pyth price feed.
    IPyth public pyth;


    /// @notice Constructor
    /// @param _pyth The address of the Pyth price feed.
    /// @param _priceId The price ID of the USDTB NAV.
    constructor(address _pyth, bytes32 _priceId) {
        priceId = _priceId;
        pyth = IPyth(_pyth);
    }

    /// @notice Wrapper function to update the underlying Pyth price feeds. Not part of the AggregatorV3 interface but useful.
    /// @param priceUpdateData The price update data.
    function updateFeeds(bytes[] calldata priceUpdateData) public payable {
        // Update the prices to the latest available values and pay the required fee for it. The `priceUpdateData` data
        // should be retrieved from our off-chain Price Service API using the `pyth-evm-js` package.
        // See section "How Pyth Works on EVM Chains" below for more information.
        uint fee = pyth.getUpdateFee(priceUpdateData);
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        // refund remaining eth
        payable(msg.sender).call{value: address(this).balance}("");
    }

    /// @notice Returns the number of decimals used in price feed output.
    /// @return The number of decimals.
    function decimals() public view virtual returns (uint8) {
        return NAV_PRICE_DECIMALS;
    }

    /// @notice Returns the description of the price feed.
    /// @return The description.
    function description() public pure returns (string memory) {
        return "USDTB by Ethena / USD";
    }

    /// @notice Returns the version of the price feed.
    /// @return The version.
    function version() public pure returns (uint256) {
        return 1;
    }

    /// @notice Returns the threshold for the price feed.
    /// @return The threshold.
    function getThreshold() public pure returns (int256) {
        return NAV_POSITIVE_THRESHOLD;
    }

    /// @notice Returns the round data for a given round ID.
    /// @param _roundId The round ID.
    /// @return roundId The round ID.
    /// @return answer The answer.
    /// @return startedAt The started at.
    /// @return updatedAt The updated at.
    /// @return answeredInRound The answered in round.
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        PythStructs.Price memory price = pyth.getPriceUnsafe(priceId);
        return (
            _roundId,
            _getPriceFromNAV(int256(price.price)),
            price.publishTime,
            price.publishTime,
            _roundId
        );
    }

    /// @notice Returns the latest round data.
    /// @return roundId The round ID.
    /// @return answer The answer.
    /// @return startedAt The started at.
    /// @return updatedAt The updated at.
    /// @return answeredInRound The answered in round.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        PythStructs.Price memory price = pyth.getPriceUnsafe(priceId);
        roundId = uint80(price.publishTime);
        return (
            roundId,
            _getPriceFromNAV(int256(price.price)),
            price.publishTime,
            price.publishTime,
            roundId
        );
    }

    /// @notice Converts NAV price to USDTB price based on a predefined sensitivity threshold.
    /// @param  answer The NAV price to convert.
    /// @return The formatted USDTB price.
    function _getPriceFromNAV(int256 answer) internal view returns (int256) {
        PythStructs.Price memory price = pyth.getPriceUnsafe(priceId);
        uint8 oracleDecimals = uint8(-1 * int8(price.expo));

        // Scale the answer to the PRICE_FEED_DECIMALS for the valid comparison.
        int256 scaledAnswer = (answer * int256(10 ** NAV_PRICE_DECIMALS)) / int256(10 ** oracleDecimals);

        return scaledAnswer >= NAV_POSITIVE_THRESHOLD ? NAV_POSITIVE_THRESHOLD : scaledAnswer;
    }
}
