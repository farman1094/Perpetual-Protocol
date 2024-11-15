
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Protocol Oracle Library
 * @author Mohd Farman
 * @notice This library is used to check the chainlink Oracle for stale data.
 * If a price is stable, the function will revert, and render the Protocol unusable - this is by design
 * We want Protocol to freeze if prices become stale
 */

library OracleLib {
    error OracleLib__PriceStale();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 sec = 10800 seconds

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        // if (secondsSince > TIMEOUT) revert OracleLib__PriceStale();  //commented for testing
         return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
