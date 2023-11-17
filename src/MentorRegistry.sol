// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IDEVMentor} from "./IDEVMentor.sol";

contract MentorRegistry is IDEVMentor {
    ///////////////////
    // Type declarations
    ///////////////////

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

    struct MentorSelectionRequest {
        address mentee;
        address[] matchingMentors;
        uint256 engagement;
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

    mapping(address mentor => Mentor) internal s_registeredMentors;
    address[] internal s_mentors;
    mapping(uint256 vrfRequestId => MentorSelectionRequest)
        internal s_mentorSelectionRequests;

    ///////////////////
    // Events
    ///////////////////

    event MentorRegistered(address indexed mentor);
    event MentorApproved(address indexed mentor);
    event MentorConfirmedSession(
        address indexed mentee,
        address indexed mentor
    );
    event MentorTipped(
        address indexed tipper,
        address indexed mentor,
        uint256 value
    );
    event MentorSelectionRequestSent(
        address indexed mentee,
        uint256 indexed requestId
    );

    ///////////////////
    // Errors
    ///////////////////

    error DEVMentor__AlreadyRegisteredAsMentor(address _mentor);
    error DEVMentor__NotAMentor(address _mentor);
    error DEVMentor__IncorrectMentee(address _mentor);

    ///////////////////
    // Modifiers
    ///////////////////

    modifier isMentor() {
        if (!s_registeredMentors[msg.sender].validated) {
            revert DEVMentor__NotAMentor(msg.sender);
        }
        _;
    }

    modifier NotRegisteredAsMentor() {
        if (s_registeredMentors[msg.sender].registered) {
            revert DEVMentor__AlreadyRegisteredAsMentor(msg.sender);
        }
        _;
    }

    modifier hasMentee(address _mentee) {
        if (s_registeredMentors[msg.sender].mentee != _mentee) {
            revert DEVMentor__IncorrectMentee(msg.sender);
        }
        _;
    }

    ////////////////////
    // Internal
    ////////////////////

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
        emit MentorRegistered(msg.sender);
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

    function isAccountMentor(address _mentor) external view returns (bool) {
        return s_registeredMentors[_mentor].validated;
    }

    function getMentorSelectionRequest(
        uint256 _requestId
    ) external view returns (MentorSelectionRequest memory) {
        return s_mentorSelectionRequests[_requestId];
    }
}
