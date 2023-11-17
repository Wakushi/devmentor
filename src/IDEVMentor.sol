// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IDEVMentor {
    enum Subject {
        BLOCKCHAIN_BASICS,
        SMART_CONTRACT_BASICS,
        ERC20,
        NFT,
        DEFI,
        DAO,
        CHAINLINK,
        SECURITY
    }

    enum Level {
        NOVICE,
        BEGINNER,
        INTERMEDIATE
    }
}
