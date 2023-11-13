// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// OpenZeppelin
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// Chainlink
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
// Custom
import {Languages} from "./Languages.sol";

error DEVMentor__RequestAlreadyOpened(address _mentee);
error DEVMentor__AlreadyRegisteredAsMentee(address _mentee);
error DEVMentor__AlreadyRegisteredAsMentor(address _mentor);
error DEVMentor__IncorrectMentor(address _mentor);
error DEVMentor__IncorrectMentee(address _mentor);
error DEVMentor__NotAMentor(address _mentor);
error DEVMentor__NotAMentee(address _mentor);
error DEVMentor__SessionDurationNotOver();
error DEVMentor__TransferFailed();
error DEVMentor__MinimumEngagementNotReached();
error DEVMentor__WrongRating();

contract DEVMentor is Languages, VRFConsumerBaseV2 {
    ///////////////////
    // Type declarations
    ///////////////////

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

    struct Mentor {
        Subject[] teachingSubjects;
        address mentee;
        uint8 yearsOfExperience;
        uint8 language;
        uint256 totalRating;
        uint256 engagement;
        uint256 sessionCount;
        bool registered;
        bool validated;
    }

    struct Mentee {
        uint256 language;
        uint256 sessionCount;
        address mentor;
        bool registered;
        bool hasRequest;
    }

    struct MenteeRequest {
        Level level;
        Subject learningSubject;
        bool accepted;
        uint256 engagement;
        uint256 valueLocked;
    }

    struct MentorSelectionRequest {
        address mentee;
        address[] matchingMentors;
        uint256 engagement;
    }

    struct Session {
        address mentor;
        address mentee;
        uint256 startTime;
        uint256 engagement;
        uint256 valueLocked;
        bool mentorConfirmed;
        bool menteeConfirmed;
    }

    ///////////////////
    // State variables
    ///////////////////

    // Chainlink VRF
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    // Core
    mapping(address mentor => Mentor) private s_registeredMentors;
    mapping(address mentee => Mentee) private s_registeredMentees;

    mapping(address mentee => MenteeRequest) private s_menteeRequests;
    mapping(uint256 vrfRequestId => MentorSelectionRequest)
        private s_mentorSelectionRequests;
    mapping(address mentee => uint256 lockedValue) private s_menteeLockedValue;
    mapping(address mentee => mapping(address mentor => Session))
        private s_sessions;

    address[] s_mentors;

    ///////////////////
    // Events
    ///////////////////

    ///////////////////
    // Modifiers
    ///////////////////

    modifier NotRegisteredAsMentee() {
        if (s_registeredMentees[msg.sender].registered) {
            revert DEVMentor__AlreadyRegisteredAsMentee(msg.sender);
        }
        _;
    }

    modifier NotRegisteredAsMentor() {
        if (s_registeredMentors[msg.sender].registered) {
            revert DEVMentor__AlreadyRegisteredAsMentor(msg.sender);
        }
        _;
    }

    modifier hasRequestOpened() {
        if (s_registeredMentees[msg.sender].hasRequest) {
            revert DEVMentor__RequestAlreadyOpened(msg.sender);
        }
        _;
    }

    modifier isMentor() {
        if (!s_registeredMentors[msg.sender].validated) {
            revert DEVMentor__NotAMentor(msg.sender);
        }
        _;
    }

    modifier isMentee() {
        if (!s_registeredMentees[msg.sender].registered) {
            revert DEVMentor__NotAMentee(msg.sender);
        }
        _;
    }

    modifier hasMentor(address _mentor) {
        if (s_registeredMentees[msg.sender].mentor != _mentor) {
            revert DEVMentor__IncorrectMentor(msg.sender);
        }
        _;
    }

    modifier hasMentee(address _mentee) {
        if (s_registeredMentors[msg.sender].mentee != _mentee) {
            revert DEVMentor__IncorrectMentee(msg.sender);
        }
        _;
    }

    modifier minimumEngagement(uint256 _engagement) {
        if (_engagement < 1 weeks) {
            revert DEVMentor__MinimumEngagementNotReached();
        }
        _;
    }

    constructor(
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        string[] memory _languages
    ) Languages(_languages) VRFConsumerBaseV2(_vrfCoordinator) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
    }

    ////////////////////
    // External
    ////////////////////

    /**
     *
     * @param _level Level of the mentee
     * @param _subject Subject the mentee wants to learn
     * @param _engagement Engagement duration in seconds
     * @notice Registers the mentee and makes a request in a single transaction
     */
    function registerAsMenteeAndMakeRequestForSession(
        Level _level,
        Subject _subject,
        uint256 _language,
        uint256 _engagement,
        address[] calldata _matchingMentors,
        address _chosenMentor
    )
        external
        payable
        NotRegisteredAsMentee
        NotRegisteredAsMentor
        minimumEngagement(_engagement)
    {
        _registerMentee(_language);
        _makeRequestForSession(
            _subject,
            _engagement,
            _level,
            _matchingMentors,
            _chosenMentor,
            msg.value
        );
    }

    function registerAsMentor(
        Subject[] calldata _teachingSubjects,
        uint256 _engagement,
        uint8 _language,
        uint8 _yearsOfExperience
    ) external NotRegisteredAsMentor minimumEngagement(_engagement) {
        _registerMentor(
            _teachingSubjects,
            _engagement,
            _language,
            _yearsOfExperience
        );
    }

    function openRequestForSession(
        Subject _subject,
        Level _level,
        uint256 _engagement,
        address[] calldata _matchingMentors,
        address _chosenMentor
    )
        external
        payable
        isMentee
        NotRegisteredAsMentor
        hasRequestOpened
        minimumEngagement(_engagement)
    {
        _makeRequestForSession(
            _subject,
            _engagement,
            _level,
            _matchingMentors,
            _chosenMentor,
            msg.value
        );
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

    ////////////////////
    // Public
    ////////////////////

    ////////////////////
    // Internal
    ////////////////////

    function _registerMentee(uint256 _language) internal {
        s_registeredMentees[msg.sender] = Mentee({
            language: _language,
            registered: true,
            mentor: address(0),
            sessionCount: 0,
            hasRequest: false
        });
    }

    function _registerMentor(
        Subject[] calldata _teachingSubjects,
        uint256 _engagement,
        uint8 _language,
        uint8 _yearsOfExperience
    ) internal {
        s_registeredMentors[msg.sender] = Mentor({
            teachingSubjects: _teachingSubjects,
            language: _language,
            engagement: _engagement,
            yearsOfExperience: _yearsOfExperience,
            mentee: address(0),
            registered: true,
            totalRating: 0,
            sessionCount: 0,
            validated: false
        });
    }

    function _makeRequestForSession(
        Subject _subject,
        uint256 _engagement,
        Level _level,
        address[] calldata _matchingMentors,
        address _chosenMentor,
        uint256 _valueLocked
    ) internal {
        // If value is sent with the request, lock it and assign to the mentee his chosen mentor
        if (_valueLocked > 0 && _chosenMentor != address(0)) {
            s_menteeLockedValue[msg.sender] = _valueLocked;
            _matchMentorWithMentee(
                _chosenMentor,
                msg.sender,
                _engagement,
                _valueLocked
            );
        }

        if (_valueLocked == 0) {
            // Open a request if there is no currently available mentor
            if (_matchingMentors.length == 0) {
                s_registeredMentees[msg.sender].hasRequest = true; // TODO: Mecanism to fulfill request
                s_menteeRequests[msg.sender] = MenteeRequest({
                    level: _level,
                    learningSubject: _subject,
                    engagement: _engagement,
                    accepted: false,
                    valueLocked: _valueLocked
                });
            } else if (_matchingMentors.length == 1) {
                // If there is only one mentor, assign him to the mentee
                _matchMentorWithMentee(
                    _matchingMentors[0],
                    msg.sender,
                    _engagement,
                    _valueLocked
                );
            } else {
                // If there are at least two mentors get random mentor
                uint256 requestId = i_vrfCoordinator.requestRandomWords(
                    i_gasLane,
                    i_subscriptionId,
                    REQUEST_CONFIRMATIONS,
                    i_callbackGasLimit,
                    NUM_WORDS
                );
                s_mentorSelectionRequests[requestId] = MentorSelectionRequest({
                    mentee: msg.sender,
                    matchingMentors: _matchingMentors,
                    engagement: _engagement
                });
            }
        }
    }

    function _cancelRequest(address _mentee) internal {
        s_registeredMentees[_mentee].hasRequest = false;
        delete s_menteeRequests[_mentee];
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

    function _createSession(
        address _mentor,
        address _mentee,
        uint256 _engagement,
        uint256 _valueLocked
    ) internal {
        s_sessions[_mentee][_mentor] = Session({
            mentor: _mentor,
            mentee: _mentee,
            startTime: block.timestamp,
            engagement: _engagement,
            valueLocked: _valueLocked,
            mentorConfirmed: false,
            menteeConfirmed: false
        });
    }

    function _validateSession(address _mentee, address _mentor) internal {
        Session storage session = s_sessions[_mentee][_mentor];
        if (session.startTime + session.engagement > block.timestamp) {
            revert DEVMentor__SessionDurationNotOver();
        }
        if (msg.sender == _mentee) {
            session.menteeConfirmed = true;
        } else {
            // safe not to check because of validateSessionAsMentor modifier
            session.mentorConfirmed = true;
        }
        if (session.menteeConfirmed && session.mentorConfirmed) {
            delete s_sessions[_mentee][_mentor];
            delete s_registeredMentors[_mentor].mentee;
            delete s_registeredMentees[_mentee].mentor;
            if (session.valueLocked > 0) {
                delete s_menteeLockedValue[_mentee];
                (bool success, ) = _mentor.call{value: session.valueLocked}("");
                if (!success) {
                    revert DEVMentor__TransferFailed();
                }
            }

            // TODO Add event
        }
    }

    function _rateSession(address _mentor, uint256 _rating) internal {
        if (_rating < 0 || _rating > 5) {
            revert DEVMentor__WrongRating();
        }
        Mentor storage mentor = s_registeredMentors[_mentor];
        mentor.totalRating += _rating;
    }

    ////////////////////
    // Internal / View
    ////////////////////

    function _getMenteeRequest() internal view returns (MenteeRequest memory) {
        return s_menteeRequests[msg.sender];
    }

    function _hasRequest() internal view returns (bool) {
        return s_registeredMentees[msg.sender].hasRequest;
    }

    function _mentorHasSubject(
        address _mentor,
        Subject _subject
    ) internal view returns (bool) {
        Subject[] memory subjects = s_registeredMentors[_mentor]
            .teachingSubjects;
        for (uint256 i = 0; i < subjects.length; ++i) {
            if (subjects[i] == _subject) {
                return true;
            }
        }
        return false;
    }

    ////////////////////
    // External / View
    ////////////////////

    function getMatchingMentors(
        Subject _subject,
        uint256 _engagement,
        uint8 _language
    ) public view returns (address[] memory) {
        uint256 mentorsLength = s_mentors.length;
        // To avoid searching in all the mentors, we could have a separate array for each subject or engagement
        address[] memory tempMatchingMentors = new address[](mentorsLength);
        uint256 matchingCount = 0;

        for (uint256 i = 0; i < mentorsLength; ++i) {
            Mentor storage mentor = s_registeredMentors[s_mentors[i]];
            if (
                mentor.mentee == address(0) &&
                mentor.engagement == _engagement &&
                mentor.language == _language &&
                _mentorHasSubject(s_mentors[i], _subject)
            ) {
                tempMatchingMentors[matchingCount] = s_mentors[i];
                matchingCount++;
            }
        }

        address[] memory matchingMentors = new address[](matchingCount); // To get correct length
        for (uint256 i = 0; i < matchingCount; ++i) {
            matchingMentors[i] = tempMatchingMentors[i];
        }

        return matchingMentors;
    }

    function getMenteeSession(
        address _mentee
    ) external view returns (Session memory) {
        return s_sessions[_mentee][s_registeredMentees[_mentee].mentor];
    }

    function getMenteeInfo(
        address _mentee
    ) external view returns (Mentee memory) {
        return s_registeredMentees[_mentee];
    }

    function getMentorInfo(
        address _mentor
    ) external view returns (Mentor memory) {
        return s_registeredMentors[_mentor];
    }

    function getMentorAverageRating(
        address _mentor
    ) external view returns (uint256 averageRating) {
        Mentor storage mentor = s_registeredMentors[_mentor];
        averageRating = mentor.totalRating / mentor.sessionCount;
    }
}
