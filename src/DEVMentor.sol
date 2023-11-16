// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// OpenZeppelin
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Chainlink
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Custom
import {MentorRegistry} from "./MentorRegistry.sol";
import {MenteeRegistry} from "./MenteeRegistry.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {Languages} from "./Languages.sol";

contract DEVMentor is
    MentorRegistry,
    MenteeRegistry,
    Languages,
    VRFConsumerBaseV2
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
        bytes32 gasLane;
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        string[] languages;
        address priceFeed;
    }

    struct MenteeRegistrationAndRequest {
        Level level;
        Subject subject;
        uint256 language;
        uint256 engagement;
        address[] matchingMentors;
        address chosenMentor;
    }

    struct MentorRegistration {
        Subject[] teachingSubjects;
        uint256 engagement;
        uint8 language;
        uint8 yearsOfExperience;
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

    error DEVMentor__TransferFailed();
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

    ////////////////////
    // External
    ////////////////////

    function registerAsMenteeAndMakeRequestForSession(
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
        NotRegisteredAsMentor
        minimumEngagement(registration.engagement)
    {
        _registerMentor(
            registration.teachingSubjects,
            registration.engagement,
            registration.language,
            registration.yearsOfExperience
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

    function validateSessionAsMentee(
        address _mentor,
        uint256 _rating
    ) external isMentee hasMentor(_mentor) {
        _validateSession(msg.sender, _mentor);
        _rateSession(_mentor, _rating);
    }

    function validateSessionAsMentor(
        address _mentee
    ) external isMentor hasMentee(_mentee) {
        _validateSession(_mentee, msg.sender);
    }

    function changeMentorEngagement(
        uint256 _engagement
    ) external isMentor minimumEngagement(_engagement) {
        s_registeredMentors[msg.sender].engagement = _engagement;
    }

    function approveMentor(address _mentor) external onlyOwner {
        // TODO : Make a special role for this
        s_registeredMentors[_mentor].validated = true;
        s_mentors.push(_mentor);
    }

    function tipMentor(address _mentor) external payable {
        (bool success, ) = _mentor.call{value: msg.value}("");
        if (!success) {
            revert DEVMentor__TransferFailed();
        }
        emit MentorTipped(msg.sender, _mentor, msg.value);
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
        }
        if (_valueLocked == 0) {
            _openSessionWithNoValueLocked(request, _valueLocked);
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
            revert DEVMentor__MinimumEngagementNotReached();
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
        MenteeRegistrationAndRequest calldata request,
        uint256 _valueLocked
    ) internal {
        if (request.matchingMentors.length == 0) {
            _openRequestForSession(
                request.level,
                request.subject,
                request.engagement,
                0
            );
        } else if (request.matchingMentors.length == 1) {
            _matchMentorWithMentee(
                request.matchingMentors[0],
                msg.sender,
                request.engagement,
                _valueLocked
            );
        } else {
            _getRandomMentor(request.matchingMentors, request.engagement);
        }
    }

    function _openRequestForSession(
        Level _level,
        Subject _subject,
        uint256 _engagement,
        uint256 _valueLocked
    ) internal {
        s_registeredMentees[msg.sender].hasRequest = true; // TODO: Mecanism to fulfill request
        s_menteeRequests[msg.sender] = MenteeRequest({
            level: _level,
            learningSubject: _subject,
            engagement: _engagement,
            accepted: false,
            valueLocked: _valueLocked
        });
        emit MenteeOpenedRequest(msg.sender);
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

    function _matchMentorWithMentee(
        address _mentor,
        address _mentee,
        uint256 _engagement,
        uint256 _valueLocked
    ) internal {
        s_registeredMentors[_mentor].mentee = _mentee;
        s_registeredMentees[_mentee].mentor = _mentor;
        s_registeredMentors[_mentor].sessionCount++;
        s_registeredMentees[_mentee].sessionCount++;
        emit MenteeMatchedWithMentor(_mentee, _mentor);
        _createSession(_mentor, _mentee, _engagement, _valueLocked);
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

    function _validateSession(address _mentee, address _mentor) internal {
        Session storage session = s_sessions[_mentee][_mentor];
        if (session.startTime + session.engagement > block.timestamp) {
            revert DEVMentor__SessionDurationNotOver();
        }
        if (msg.sender == _mentee) {
            session.menteeConfirmed = true;
            emit MenteeConfirmedSession(_mentee, _mentor);
        } else {
            // safe not to check because of validateSessionAsMentor modifier
            session.mentorConfirmed = true;
            emit MentorConfirmedSession(_mentee, _mentor);
        }
        if (session.menteeConfirmed && session.mentorConfirmed) {
            _completeSession(_mentor, _mentee, session.valueLocked);
        }
    }

    function _completeSession(
        address _mentor,
        address _mentee,
        uint256 _valueLocked
    ) internal {
        delete s_sessions[_mentee][_mentor];
        delete s_registeredMentors[_mentor].mentee;
        delete s_registeredMentees[_mentee].mentor;
        if (_valueLocked > 0) {
            delete s_menteeLockedValue[_mentee];
            (bool success, ) = _mentor.call{value: _valueLocked}("");
            if (!success) {
                revert DEVMentor__TransferFailed();
            }
            emit MenteeValueSent(_mentee, _mentor, _valueLocked);
        }
        emit SessionValidated(_mentee, _mentor);
    }

    function _rateSession(address _mentor, uint256 _rating) internal {
        if (_rating < 0 || _rating > 5) {
            revert DEVMentor__WrongRating();
        }
        Mentor storage mentor = s_registeredMentors[_mentor];
        mentor.totalRating += _rating;
        emit SessionRated(_mentor, _rating);
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
