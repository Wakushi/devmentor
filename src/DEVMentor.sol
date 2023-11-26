// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// OpenZeppelin
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Chainlink
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Custom
import {SessionRegistry} from "./SessionRegistry.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {Languages} from "./Languages.sol";

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
        string baseURI;
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
    )
        Languages(config.languages)
        VRFConsumerBaseV2(config.vrfCoordinator)
        SessionRegistry(config.baseURI)
    {
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
            _mintMenteeBadge(msg.sender, _badgeId);
        }
        if (s_registeredMentors[msg.sender].registered) {
            _mintMentorBadge(msg.sender, _badgeId);
        }
    }

    function claimMentorReward(uint256 rewardId) external isMentor {
        _claimReward(msg.sender, rewardId);
    }

    ////////////////////
    // Admin
    ////////////////////

    function addLanguage(string memory _language) external onlyOwner {
        _addLanguage(_language);
    }

    function approveMentor(address _mentor) external onlyOwner {
        s_registeredMentors[_mentor].validated = true;
        s_mentors.push(_mentor);
    }

    function addReward(
        uint256 price,
        uint256 totalSupply,
        string memory metadataURI
    ) external onlyOwner {
        _addReward(price, totalSupply, metadataURI);
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

    function getEthPrice() external view returns (uint256) {
        (, int256 price, , , ) = s_priceFeed.latestRoundData();
        return uint256(price);
    }
}
