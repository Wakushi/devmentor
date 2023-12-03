// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// OpenZeppelin
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Chainlink
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Custom
import {SessionRegistry} from "./SessionRegistry.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {Languages} from "./Languages.sol";

/**
 * @title DEVMentor - A Mentor Matching Platform for Developers built during Chainlink Constellation Hackathon 2023
 * @author Makushi
 * @notice This contract is the main entry point for the DEVMentor platform
 * @dev Implements Chainlink VRF, Chainlink Automation, Chainlink Data Feeds, and Chainlink Functions.
 */
contract DEVMentor is
    SessionRegistry,
    VRFConsumerBaseV2,
    ReentrancyGuard,
    Languages
{
    ///////////////////
    // Type declarations
    ///////////////////

    using PriceConverter for uint256;

    struct ChainlinkVRFConfig {
        uint16 requestConfirmations;
        uint32 numWords;
        VRFCoordinatorV2Interface vrfCoordinator;
        bytes32 gasLane;
        uint64 subscriptionId;
        uint32 callbackGasLimit;
    }

    struct DEVMentorConfig {
        address vrfCoordinator;
        address priceFeed;
        bytes32 gasLane;
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        string[] languages;
    }

    ///////////////////
    // State variables
    ///////////////////

    // Chainlink VRF
    ChainlinkVRFConfig private vrfConfig;

    // Chainlink Data Feed
    AggregatorV3Interface private s_priceFeed;
    uint256 public constant MINIMUM_LOCKED_VALUE = 5 * 10 ** 18;

    ///////////////////
    // Errors
    ///////////////////

    error DEVMentor__NotEnoughLockedValue();

    ///////////////////
    // Functions
    ///////////////////

    constructor(
        DEVMentorConfig memory config
    ) Languages(config.languages) VRFConsumerBaseV2(config.vrfCoordinator) {
        vrfConfig = ChainlinkVRFConfig({
            requestConfirmations: 3,
            numWords: 1,
            vrfCoordinator: VRFCoordinatorV2Interface(config.vrfCoordinator),
            gasLane: config.gasLane,
            subscriptionId: config.subscriptionId,
            callbackGasLimit: config.callbackGasLimit
        });
        s_priceFeed = AggregatorV3Interface(config.priceFeed);
    }

    receive() external payable {}

    fallback() external payable {}

    ////////////////////
    // External / Public
    ////////////////////

    function registerAsMenteeAndOpenSession(
        MenteeRegistrationAndRequest calldata request
    )
        external
        payable
        NotRegisteredAsMentee
        NotRegisteredAsMentor
        minimumEngagement(request.engagement)
    {
        _registerMentee(request.language);
        _makeRequestForSession(request, msg.value);
    }

    function registerAsMentor(
        MentorRegistration calldata registration
    )
        external
        NotRegisteredAsMentee
        NotRegisteredAsMentor
        minimumEngagement(registration.engagement)
    {
        _registerMentor(
            registration.teachingSubjects,
            registration.engagement,
            registration.language,
            registration.yearsOfExperience,
            registration.contact
        );
    }

    function openRequestForSession(
        MenteeRegistrationAndRequest calldata request
    )
        external
        payable
        isMentee
        NotRegisteredAsMentor
        hasRequestOpened
        minimumEngagement(request.engagement)
    {
        _makeRequestForSession(request, msg.value);
    }

    function cancelRequestForSession() external {
        _cancelRequest(msg.sender);
    }

    function cancelSessionAsMentee(
        address _mentor
    ) external isMentee nonReentrant {
        _cancelSession(msg.sender, _mentor);
    }

    function cancelSessionAsMentor(
        address _mentee
    ) external isMentor nonReentrant {
        _cancelSession(_mentee, msg.sender);
    }

    function validateSessionAsMentee(
        address _mentor,
        uint256 _rating
    ) external payable isMentee hasMentor(_mentor) nonReentrant {
        _validateSession(msg.sender, _mentor);
        _rateSession(_mentor, _rating);
        if (msg.value > 0) {
            (bool success, ) = _mentor.call{value: msg.value}("");
            if (!success) {
                revert DEVMentor__TransferFailed();
            }
            emit MentorTipped(msg.sender, _mentor, msg.value);
        }
    }

    function validateSessionAsMentor(
        address _mentee
    ) external isMentor hasMentee(_mentee) nonReentrant {
        _validateSession(_mentee, msg.sender);
    }

    function changeMentorEngagement(
        uint256 _engagement
    ) external isMentor minimumEngagement(_engagement) {
        s_registeredMentors[msg.sender].engagement = _engagement;
    }

    function tipMentor(address _mentor) external payable {
        (bool success, ) = _mentor.call{value: msg.value}("");
        if (!success) {
            revert DEVMentor__TransferFailed();
        }
        emit MentorTipped(msg.sender, _mentor, msg.value);
    }

    function burnXpForBadge(uint256 _badgeId) external {
        if (s_registeredMentees[msg.sender].registered) {
            s_rewardManager.mintMenteeBadge(msg.sender, _badgeId);
        }
        if (s_registeredMentors[msg.sender].registered) {
            s_rewardManager.mintMentorBadge(msg.sender, _badgeId);
        }
    }

    function claimMentorReward(uint256 rewardId) external isMentor {
        s_rewardManager.claimReward(msg.sender, rewardId);
    }

    /**
     * @dev Allows mentors to redeem a reward by triggering an external API call via Chainlink Functions DON.
     * This function is called by a mentor who wishes to redeem a reward identified by `_rewardId`.
     * The function delegates the redemption process to an external `RewardManager` contract (see FunctionsConsumer.sol _sendMailerRequest())
     *
     * Upon successful execution, an email containing reward information is sent to the user via Chainlink DON.
     *
     * @param _rewardId The unique identifier of the reward to be redeemed.
     * @param _args Additional arguments required for the redemption process. This could include
     * information such as the mentor's email address or other relevant details needed to process the reward.
     *
     * Requirements:
     * - The caller must be a registered mentor.
     */
    function redeemReward(
        uint256 _rewardId,
        string[] calldata _args
    ) external isMentor {
        s_rewardManager.redeemReward(msg.sender, _rewardId, _args);
    }

    ////////////////////
    // Admin
    ////////////////////

    function addLanguage(string memory _language) external onlyOwner {
        _addLanguage(_language);
    }

    function addReward(
        uint256 price,
        uint256 totalSupply,
        uint256 ethAmount,
        string memory metadataURI,
        bool _externalPrice
    ) external onlyOwner {
        s_rewardManager.addReward(
            price,
            totalSupply,
            ethAmount,
            metadataURI,
            _externalPrice
        );
    }

    function setRewardBaseUri(string memory _baseURI) external onlyOwner {
        s_rewardManager.setBaseUri(_baseURI);
    }

    function setRewardTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) external onlyOwner {
        s_rewardManager.setTokenURI(tokenId, _tokenURI);
    }

    function setDonId(bytes32 newDonId) external onlyOwner {
        s_rewardManager.setDonId(newDonId);
    }

    function setCFSubId(uint64 _subscriptionId) external onlyOwner {
        s_rewardManager.setCFSubId(_subscriptionId);
    }

    function setSecretReference(
        bytes calldata _secretReference
    ) external onlyOwner {
        s_rewardManager.setSecretReference(_secretReference);
    }

    /**
     * @notice Ownership control modifier removed for Evaluation Purposes by Testing Teams and Hackathon Judges.
     * This function is designed to facilitate the approval of mentors for testing purposes.
     * Ownership control should be re-added prior to production deployment (using OpenZeppelin Access Control & Roles)
     */
    function adminApproveMentor(address _mentor) external {
        s_registeredMentors[_mentor].validated = true;
        s_mentors.push(_mentor);
    }

    /**
     * @notice For Evaluation Purposes by Testing Teams and Hackathon Judges - Intended for Removal Prior to Production Deployment
     * This function is designed to facilitate the minting of XP tokens for testing purposes.
     */
    function testMintXp(address _to, uint256 _amount) external {
        s_rewardManager.adminMintXp(_to, _amount);
    }

    /**
     * @notice For Evaluation Purposes by Testing Teams and Hackathon Judges - Intended for Removal Prior to Production Deployment
     * This function is designed to facilitate the minting of Mentor tokens for testing purposes.
     */
    function testMintMentorToken(address _to, uint256 _amount) external {
        s_rewardManager.adminMintMentorToken(_to, _amount);
    }

    ////////////////////
    // Internal
    ////////////////////

    function _makeRequestForSession(
        MenteeRegistrationAndRequest calldata request,
        uint256 _valueLocked
    ) internal {
        if (_valueLocked > 0 && request.chosenMentor != address(0)) {
            _openSessionWithValueLocked(
                _valueLocked,
                request.chosenMentor,
                request.engagement
            );
        } else {
            _openSessionWithNoValueLocked(request);
        }
    }

    /**
     * @dev Opens a session for the mentee with the selected mentor.
     * We check if the mentee has enough locked value (min. 5$) to open a session using Chainlink Data Feeds.
     */
    function _openSessionWithValueLocked(
        uint256 _valueLocked,
        address _chosenMentor,
        uint256 _engagement
    ) internal {
        if (
            _valueLocked.getConversionRate(s_priceFeed) < MINIMUM_LOCKED_VALUE
        ) {
            revert DEVMentor__NotEnoughLockedValue();
        }
        s_menteeLockedValue[msg.sender] = _valueLocked;
        _matchMentorWithMentee(
            _chosenMentor,
            msg.sender,
            _engagement,
            _valueLocked
        );
        emit MenteeLockedValue(msg.sender, _valueLocked);
    }

    function _openSessionWithNoValueLocked(
        MenteeRegistrationAndRequest calldata request
    ) internal {
        if (request.matchingMentors.length == 0) {
            _openRequestForSession(
                request.level,
                request.subject,
                request.engagement
            );
        } else if (request.matchingMentors.length == 1) {
            _matchMentorWithMentee(
                request.matchingMentors[0],
                msg.sender,
                request.engagement,
                0
            );
        } else {
            _getRandomMentor(request.matchingMentors, request.engagement);
        }
    }

    /**
     * @dev Requests a random number from Chainlink VRF to select a random mentor
     * from the provided list of matching mentors. The request ID is mapped to the
     * mentor selection request for later retrieval in `fulfillRandomWords`.
     *
     * Emits a `MentorSelectionRequestSent` event upon successful request submission.
     *
     * @param _matchingMentors An array of addresses representing mentors that match
     * the mentee's criteria.
     * @param _engagement The duration of the mentorship engagement.
     */
    function _getRandomMentor(
        address[] calldata _matchingMentors,
        uint256 _engagement
    ) internal {
        uint256 requestId = vrfConfig.vrfCoordinator.requestRandomWords(
            vrfConfig.gasLane,
            vrfConfig.subscriptionId,
            vrfConfig.requestConfirmations,
            vrfConfig.callbackGasLimit,
            vrfConfig.numWords
        );
        s_mentorSelectionRequests[requestId] = MentorSelectionRequest({
            mentee: msg.sender,
            matchingMentors: _matchingMentors,
            engagement: _engagement
        });
        emit MentorSelectionRequestSent(msg.sender, requestId);
    }

    /**
     * @dev Callback function used by Chainlink VRF to deliver the random number.
     * Selects a random mentor from the list of matching mentors based on the random
     * number provided. Initiates the mentorship process by matching the selected
     * mentor with the mentee.
     *
     * This function can only be called by the Chainlink VRF coordinator.
     *
     * @param requestId The request ID that maps to the original mentor selection request.
     * @param randomWords An array containing the random number(s) provided by Chainlink VRF.
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        MentorSelectionRequest storage request = s_mentorSelectionRequests[
            requestId
        ];
        uint256 randomIndex = randomWords[0] % request.matchingMentors.length;
        address randomMentor = request.matchingMentors[randomIndex];
        _matchMentorWithMentee(
            randomMentor,
            request.mentee,
            request.engagement,
            0
        );
    }

    ////////////////////
    // External / View
    ////////////////////

    function getMenteeSession(
        address _mentee
    ) external view returns (Session memory) {
        return s_sessions[_mentee][s_registeredMentees[_mentee].mentor];
    }

    /**
     * @dev Returns the current price of ETH in USD for dApp frontend usage.
     */
    function getEthPrice() external view returns (uint256) {
        (, int256 price, , , ) = s_priceFeed.latestRoundData();
        return uint256(price);
    }
}
