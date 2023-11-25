// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {MentorRegistry} from "./MentorRegistry.sol";
import {MenteeRegistry} from "./MenteeRegistry.sol";
import {RewardManager} from "./RewardManager.sol";

contract SessionRegistry is MentorRegistry, MenteeRegistry, RewardManager {
    ///////////////////
    // Type declarations
    ///////////////////

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

    mapping(address mentee => mapping(address mentor => Session))
        internal s_sessions;

    ///////////////////
    // Events
    ///////////////////

    event RequestCancelled(address indexed mentee);
    event SessionCreated(
        address indexed mentee,
        address indexed mentor,
        uint256 engagement,
        uint256 valueLocked
    );
    event SessionValidated(address indexed mentee, address indexed mentor);
    event SessionRated(address indexed mentor, uint256 rating);

    ///////////////////
    // Error
    ///////////////////

    error DEVMentor__RequestAlreadyOpened(address _mentee);
    error DEVMentor__SessionDurationNotOver();
    error DEVMentor__MinimumEngagementNotReached();
    error DEVMentor__WrongRating();

    ///////////////////
    // Modifiers
    ///////////////////

    modifier hasRequestOpened() {
        if (s_registeredMentees[msg.sender].hasRequest) {
            revert DEVMentor__RequestAlreadyOpened(msg.sender);
        }
        _;
    }

    modifier minimumEngagement(uint256 _engagement) {
        if (_engagement < 1 weeks) {
            revert DEVMentor__MinimumEngagementNotReached();
        }
        _;
    }

    constructor(string memory baseURI) RewardManager(baseURI) {}

    ////////////////////
    // External / Public
    ////////////////////

    function updateSessionEngagement(
        address _mentee,
        address _mentor,
        uint256 _engagement
    ) external {
        s_sessions[_mentee][_mentor].engagement = _engagement;
    }

    ////////////////////
    // Internal
    ////////////////////

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
        emit SessionCreated(_mentee, _mentor, _engagement, _valueLocked);
    }

    function _openRequestForSession(
        Level _level,
        Subject _subject,
        uint256 _engagement
    ) internal {
        s_registeredMentees[msg.sender].hasRequest = true;
        s_menteeRequests[msg.sender] = MenteeRequest({
            level: _level,
            learningSubject: _subject,
            engagement: _engagement
        });
        s_menteeWithRequest.push(msg.sender);
        emit MenteeOpenedRequest(msg.sender);
    }

    function _cancelRequest(address _mentee) internal {
        s_registeredMentees[_mentee].hasRequest = false;
        delete s_menteeRequests[_mentee];
        emit RequestCancelled(_mentee);
    }

    function _matchMentorWithMentee(
        address _mentor,
        address _mentee,
        uint256 _engagement,
        uint256 _valueLocked
    ) internal {
        s_registeredMentors[_mentor].mentee = _mentee;
        s_registeredMentees[_mentee].mentor = _mentor;
        emit MenteeMatchedWithMentor(_mentee, _mentor);
        _createSession(_mentor, _mentee, _engagement, _valueLocked);
    }

    ////////////////////
    // External / View
    ////////////////////

    function getSession(
        address _mentee,
        address _mentor
    ) external view returns (Session memory) {
        return s_sessions[_mentee][_mentor];
    }
}
