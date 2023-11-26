// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IRewardManager {
    struct Reward {
        uint256 id;
        uint256 price;
        uint256 totalSupply;
        uint256 remainingSupply;
        string metadataURI;
    }
}
