// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IDEVMentor} from "./IDEVMentor.sol";

contract MenteeRegistry is IDEVMentor {
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
        uint256 engagement;
    }

    struct MenteeRegistrationAndRequest {
        Level level;
        Subject subject;
        uint256 language;
        uint256 engagement;
        address[] matchingMentors;
        address chosenMentor;
    }

    mapping(address mentee => Mentee) internal s_registeredMentees;
    mapping(address mentee => MenteeRequest) internal s_menteeRequests;
    mapping(address mentee => uint256 lockedValue) internal s_menteeLockedValue;
    address[] internal s_menteeWithRequest;

    event MenteeRegistered(address indexed mentee);
    event MenteeOpenedRequest(address indexed mentee);
    event MenteeLockedValue(address indexed mentee, uint256 valueLocked);
    event MenteeMatchedWithMentor(
        address indexed mentee,
        address indexed mentor
    );
    event MenteeConfirmedSession(
        address indexed mentee,
        address indexed mentor
    );
    event MenteeValueSent(
        address indexed mentee,
        address indexed mentor,
        uint256 value
    );

    error DEVMentor__AlreadyRegisteredAsMentee(address _mentee);
    error DEVMentor__NotAMentee(address _mentor);
    error DEVMentor__IncorrectMentor(address _mentor);

    modifier NotRegisteredAsMentee() {
        if (s_registeredMentees[msg.sender].registered) {
            revert DEVMentor__AlreadyRegisteredAsMentee(msg.sender);
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

    function _registerMentee(uint256 _language) internal {
        s_registeredMentees[msg.sender] = Mentee({
            language: _language,
            registered: true,
            mentor: address(0),
            sessionCount: 0,
            hasRequest: false
        });
        emit MenteeRegistered(msg.sender);
    }

    function getMenteeInfo(
        address _mentee
    ) external view returns (Mentee memory) {
        return s_registeredMentees[_mentee];
    }

    function getMenteeRequest(
        address _mentee
    ) external view returns (MenteeRequest memory) {
        return s_menteeRequests[_mentee];
    }

    function isAccountMentee(address _mentee) external view returns (bool) {
        return s_registeredMentees[_mentee].registered;
    }
}
