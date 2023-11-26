// SPDX-License-Identifier: MIT

import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IRewardManager} from "./IRewardManager.sol";

pragma solidity ^0.8.18;

contract RewardManager is ERC1155URIStorage, IRewardManager {
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

    error DEVMentor__InvalidBadgeId(uint256 _badgeId);
    error DEVMentor__PreviousBadgeRequired(uint256 _badgeId);
    error DEVMentor__NotEnoughXP(uint256 _badgeId);
    error DEVMentor__RewardSoldOut(uint256 _rewardId);
    error DEVMentor__InsufficientBalance(uint256 _rewardId);

    modifier hasEnoughXp(address _user, uint256 _badgeId) {
        if (balanceOf(_user, XP_TOKEN_ID) < getBadgeXpCost(_badgeId)) {
            revert DEVMentor__NotEnoughXP(_badgeId);
        }
        _;
    }

    constructor(string memory baseURI) ERC1155(baseURI) {}

    function _mintXP(address _to, uint256 _engagement) internal {
        uint256 totalXP = _calculateTotalTokens(
            XP_PER_SESSION,
            XP_INCREMENT_FACTOR,
            XP_MONTHLY_BONUS,
            _engagement
        );
        _mint(_to, XP_TOKEN_ID, totalXP, "");
        emit XPGained(_to, totalXP);
    }

    function _mintMentorToken(address _mentor, uint256 _engagement) internal {
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

    function _mintMenteeBadge(address user, uint256 badgeId) internal {
        _mintBadge(user, badgeId, NEW_NAVIGATOR_ID, EDU_ELITE_ID);
    }

    function _mintMentorBadge(address user, uint256 badgeId) internal {
        _mintBadge(user, badgeId, GUIDANCE_GURU_ID, LEGEND_LUMINARY_ID);
    }

    function _addReward(
        uint256 price,
        uint256 totalSupply,
        string memory metadataURI
    ) internal {
        rewards[nextTokenId] = Reward({
            id: nextTokenId,
            price: price,
            totalSupply: totalSupply,
            remainingSupply: totalSupply,
            metadataURI: metadataURI
        });
        availableRewardIds.push(nextTokenId);
        emit RewardAdded(nextTokenId, price, totalSupply, metadataURI);
        ++nextTokenId;
    }

    function _claimReward(address _mentor, uint256 rewardId) internal {
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
            if (
                availableRewardIds[i] == rewardId &&
                availableRewardIds.length > 1
            ) {
                availableRewardIds[i] = availableRewardIds[
                    availableRewardIds.length - 1
                ];
                availableRewardIds.pop();
                emit RewardSoldOut(rewardId);
                break;
            }
        }
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
}
