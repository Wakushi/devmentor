// SPDX-License-Identifier: MIT

import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {FunctionsConsumer} from "./FunctionsConsumer.sol";

pragma solidity ^0.8.18;

contract RewardManager is ERC1155URIStorage, FunctionsConsumer {
    struct Reward {
        uint256 id;
        uint256 price;
        uint256 ethAmount;
        uint256 totalSupply;
        uint256 remainingSupply;
        string metadataURI;
        bool externalPrice;
    }

    uint256 public constant MENTOR_TOKEN_ID = 0;
    uint256 public constant XP_TOKEN_ID = 1;
    uint256 public nextTokenId = 12;

    uint256 public constant NEW_NAVIGATOR_ID = 2;
    uint256 public constant SKILL_SEEKER_ID = 3;
    uint256 public constant KNOWLEDGE_KNIGHT_ID = 4;
    uint256 public constant WISDOM_WARRIOR_ID = 5;
    uint256 public constant EDU_ELITE_ID = 6;

    uint256 public constant NEW_NAVIGATOR_XP = 500;
    uint256 public constant SKILL_SEEKER_XP = 1500;
    uint256 public constant KNOWLEDGE_KNIGHT_XP = 3000;
    uint256 public constant WISDOM_WARRIOR_XP = 5000;
    uint256 public constant EDU_ELITE_XP = 8000;

    uint256 public constant GUIDANCE_GURU_ID = 7;
    uint256 public constant MENTOR_MAESTRO_ID = 8;
    uint256 public constant SAGE_SHERPA_ID = 9;
    uint256 public constant PIONEER_PATRON_ID = 10;
    uint256 public constant LEGEND_LUMINARY_ID = 11;

    uint256 public constant GUIDANCE_GURU_XP = 1000;
    uint256 public constant MENTOR_MAESTRO_XP = 2500;
    uint256 public constant SAGE_SHERPA_XP = 4500;
    uint256 public constant PIONEER_PATRON_XP = 7000;
    uint256 public constant LEGEND_LUMINARY_XP = 10000;

    uint256 public constant XP_PER_SESSION = 100;
    uint256 public constant XP_INCREMENT_FACTOR = 100;
    uint256 public constant XP_MONTHLY_BONUS = 30;

    uint256 public constant MENTOR_TOKEN_PER_SESSION = 150;
    uint256 public constant MENTOR_TOKEN_INCREMENT_FACTOR = 150;
    uint256 public constant MENTOR_TOKEN_MONTHLY_BONUS = 45;

    mapping(address => uint256) private userLastMintedBadgeId;
    mapping(uint256 => Reward) public rewards;
    uint256[] public availableRewardIds;
    uint256[] public rewardsHistory;

    event XPGained(address indexed user, uint256 indexed amount);
    event RewardAdded(
        uint256 indexed rewardId,
        uint256 price,
        uint256 totalSupply,
        string metadataURI
    );
    event RewardClaimed(address indexed user, uint256 indexed rewardId);
    event BadgeMinted(address indexed user, uint256 indexed badgeId);
    event MentorTokensGained(address indexed user, uint256 indexed amount);
    event RewardSoldOut(uint256 indexed rewardId);
    event RewardRedeemed(address indexed user, uint256 indexed rewardId);

    error DEVMentor__InvalidBadgeId(uint256 _badgeId);
    error DEVMentor__PreviousBadgeRequired(uint256 _badgeId);
    error DEVMentor__NotEnoughXP(uint256 _badgeId);
    error DEVMentor__RewardSoldOut(uint256 _rewardId);
    error DEVMentor__InsufficientBalance(uint256 _rewardId);
    error DEVMentor__InvalidRewardId(uint256 _rewardId);
    error DEVMentor__TransferFailed();

    modifier hasEnoughXp(address _user, uint256 _badgeId) {
        if (balanceOf(_user, XP_TOKEN_ID) < getBadgeXpCost(_badgeId)) {
            revert DEVMentor__NotEnoughXP(_badgeId);
        }
        _;
    }

    constructor(
        string memory _baseURI,
        address _router,
        bytes32 _donId
    ) ERC1155(_baseURI) FunctionsConsumer(_router, _donId) {}

    function redeemReward(
        address _to,
        uint256 _rewardId,
        string[] calldata _functionArgs
    ) external onlyOwner {
        if (balanceOf(_to, _rewardId) <= 0) {
            revert DEVMentor__InsufficientBalance(_rewardId);
        }
        if (_rewardId <= LEGEND_LUMINARY_ID) {
            revert DEVMentor__InvalidRewardId(_rewardId);
        }
        Reward memory reward = rewards[uint256(_rewardId)];
        _burn(_to, _rewardId, 1);
        if (reward.externalPrice) {
            _sendMailerRequest(_functionArgs);
        }
        if (reward.ethAmount > 0) {
            (bool success, ) = _to.call{value: reward.ethAmount}("");
            if (!success) {
                revert DEVMentor__TransferFailed();
            }
        }
        emit RewardRedeemed(_to, _rewardId);
    }

    function mintXP(address _to, uint256 _engagement) external onlyOwner {
        uint256 totalXP = _calculateTotalTokens(
            XP_PER_SESSION,
            XP_INCREMENT_FACTOR,
            XP_MONTHLY_BONUS,
            _engagement
        );
        _mint(_to, XP_TOKEN_ID, totalXP, "");
        emit XPGained(_to, totalXP);
    }

    function mintMentorToken(
        address _mentor,
        uint256 _engagement
    ) external onlyOwner {
        uint256 totalTokens = _calculateTotalTokens(
            MENTOR_TOKEN_PER_SESSION,
            MENTOR_TOKEN_INCREMENT_FACTOR,
            MENTOR_TOKEN_MONTHLY_BONUS,
            _engagement
        );
        _mint(_mentor, MENTOR_TOKEN_ID, totalTokens, "");
        emit MentorTokensGained(_mentor, totalTokens);
    }

    function _mintBadge(
        address user,
        uint256 badgeId,
        uint256 minBadgeId,
        uint256 maxBadgeId
    ) internal hasEnoughXp(user, badgeId) {
        if (badgeId < minBadgeId || badgeId > maxBadgeId) {
            revert DEVMentor__InvalidBadgeId(badgeId);
        }

        uint256 requiredBadgeId = (badgeId == minBadgeId) ? 0 : badgeId - 1;

        if (requiredBadgeId != 0 && balanceOf(user, requiredBadgeId) == 0) {
            revert DEVMentor__PreviousBadgeRequired(badgeId);
        }

        userLastMintedBadgeId[user] = badgeId;
        if (requiredBadgeId != 0) {
            _burn(user, requiredBadgeId, 1);
        }
        _burn(user, XP_TOKEN_ID, getBadgeXpCost(badgeId));
        _mint(user, badgeId, 1, "");
        emit BadgeMinted(user, badgeId);
    }

    function mintMenteeBadge(address user, uint256 badgeId) external onlyOwner {
        _mintBadge(user, badgeId, NEW_NAVIGATOR_ID, EDU_ELITE_ID);
    }

    function mintMentorBadge(address user, uint256 badgeId) external onlyOwner {
        _mintBadge(user, badgeId, GUIDANCE_GURU_ID, LEGEND_LUMINARY_ID);
    }

    function addReward(
        uint256 _price,
        uint256 _totalSupply,
        uint256 _ethAmount,
        string memory _metadataURI,
        bool _externalPrice
    ) external onlyOwner {
        rewards[nextTokenId] = Reward({
            id: nextTokenId,
            price: _price,
            ethAmount: _ethAmount,
            totalSupply: _totalSupply,
            remainingSupply: _totalSupply,
            metadataURI: _metadataURI,
            externalPrice: _externalPrice
        });
        availableRewardIds.push(nextTokenId);
        rewardsHistory.push(nextTokenId);
        emit RewardAdded(nextTokenId, _price, _totalSupply, _metadataURI);
        ++nextTokenId;
    }

    function claimReward(address _mentor, uint256 rewardId) external onlyOwner {
        Reward storage reward = rewards[rewardId];
        if (reward.remainingSupply == 0) {
            revert DEVMentor__RewardSoldOut(rewardId);
        }
        if (reward.price > balanceOf(_mentor, MENTOR_TOKEN_ID)) {
            revert DEVMentor__InsufficientBalance(rewardId);
        }

        reward.remainingSupply--;
        if (reward.remainingSupply == 0) {
            _removeReward(rewardId);
        }
        _burn(_mentor, MENTOR_TOKEN_ID, reward.price);
        _mint(_mentor, rewardId, 1, "");
        emit RewardClaimed(_mentor, rewardId);
    }

    function _removeReward(uint256 rewardId) internal {
        for (uint256 i = 0; i < availableRewardIds.length; ++i) {
            if (availableRewardIds[i] == rewardId) {
                availableRewardIds[i] = availableRewardIds[
                    availableRewardIds.length - 1
                ];
                availableRewardIds.pop();
                emit RewardSoldOut(rewardId);
                break;
            }
        }
    }

    function setBaseUri(string memory _baseURI) external onlyOwner {
        _setBaseURI(_baseURI);
    }

    function setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) external onlyOwner {
        _setURI(tokenId, _tokenURI);
    }

    function adminMintXp(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, XP_TOKEN_ID, _amount, "");
        emit XPGained(_to, _amount);
    }

    function adminMintMentorToken(
        address _to,
        uint256 _amount
    ) external onlyOwner {
        _mint(_to, MENTOR_TOKEN_ID, _amount, "");
        emit MentorTokensGained(_to, _amount);
    }

    function getBadgeXpCost(uint256 badgeId) public pure returns (uint256) {
        if (badgeId == NEW_NAVIGATOR_ID) return NEW_NAVIGATOR_XP;
        if (badgeId == SKILL_SEEKER_ID) return SKILL_SEEKER_XP;
        if (badgeId == KNOWLEDGE_KNIGHT_ID) return KNOWLEDGE_KNIGHT_XP;
        if (badgeId == WISDOM_WARRIOR_ID) return WISDOM_WARRIOR_XP;
        if (badgeId == EDU_ELITE_ID) return EDU_ELITE_XP;

        if (badgeId == GUIDANCE_GURU_ID) return GUIDANCE_GURU_XP;
        if (badgeId == MENTOR_MAESTRO_ID) return MENTOR_MAESTRO_XP;
        if (badgeId == SAGE_SHERPA_ID) return SAGE_SHERPA_XP;
        if (badgeId == PIONEER_PATRON_ID) return PIONEER_PATRON_XP;
        if (badgeId == LEGEND_LUMINARY_ID) return LEGEND_LUMINARY_XP;

        revert DEVMentor__InvalidBadgeId(badgeId);
    }

    function _calculateTotalTokens(
        uint256 baseAmount,
        uint256 incrementFactor,
        uint256 monthlyBonus,
        uint256 _engagement
    ) internal pure returns (uint256) {
        uint256 totalTokens = baseAmount;

        if (_engagement > 1 weeks) {
            totalTokens +=
                incrementFactor *
                ((_engagement - 1 weeks) / 1 weeks);
        }

        if (_engagement >= 4 weeks) {
            totalTokens += monthlyBonus;
        }

        return totalTokens;
    }

    function getUserXp(address _user) external view returns (uint256) {
        return balanceOf(_user, XP_TOKEN_ID);
    }

    function getUserMentorTokens(
        address _user
    ) external view returns (uint256) {
        return balanceOf(_user, MENTOR_TOKEN_ID);
    }

    function getUserBadgeId(address _user) external view returns (uint256) {
        return userLastMintedBadgeId[_user];
    }

    function getAvailableRewardIds() external view returns (uint256[] memory) {
        return availableRewardIds;
    }

    function getRewardById(
        uint256 rewardId
    ) external view returns (Reward memory) {
        return rewards[rewardId];
    }

    function getUserRewards(
        address user
    ) external view returns (uint256[] memory) {
        uint256 rewardLength = rewardsHistory.length;
        uint256[] memory userRewards = new uint256[](rewardLength);
        uint256 count = 0;
        for (uint256 i = 0; i < rewardLength; ++i) {
            uint256 rewardId = rewardsHistory[i];
            if (balanceOf(user, rewardId) > 0) {
                userRewards[count] = rewardId;
                ++count;
            }
        }
        uint256[] memory actualUserRewards = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            actualUserRewards[i] = userRewards[i];
        }
        return actualUserRewards;
    }
}
