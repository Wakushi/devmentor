// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IRewardManager {
    function mintXP(address _to, uint256 _engagement) external;

    function mintMentorToken(address _mentor, uint256 _engagement) external;

    function mintMenteeBadge(address user, uint256 badgeId) external;

    function mintMentorBadge(address user, uint256 badgeId) external;

    function claimReward(address _mentor, uint256 rewardId) external;

    function setBaseUri(string memory _baseURI) external;

    function setTokenURI(uint256 tokenId, string memory _tokenURI) external;

    function adminMintXp(address _to, uint256 _amount) external;

    function adminMintMentorToken(address _to, uint256 _amount) external;

    function redeemReward(
        address _to,
        uint256 _rewardId,
        string[] calldata _functionArgs
    ) external;

    function addReward(
        uint256 _price,
        uint256 _totalSupply,
        uint256 _ethAmount,
        string memory _metadataURI,
        bool _externalPrice
    ) external;

    function setDonId(bytes32 newDonId) external;

    function setCFSubId(uint64 _subscriptionId) external;

    function setSecretReference(bytes calldata _secretReference) external;
}
