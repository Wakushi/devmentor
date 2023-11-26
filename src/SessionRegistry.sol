// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MentorRegistry} from "./MentorRegistry.sol";
import {MenteeRegistry} from "./MenteeRegistry.sol";
import {RewardManager} from "./RewardManager.sol";
import {Languages} from "./Languages.sol";

contract SessionRegistry is
    Ownable,
    MentorRegistry,
    MenteeRegistry,
    RewardManager
{
    struct Session {
        address mentor;
        address mentee;
        uint256 startTime;
        uint256 engagement;
        uint256 valueLocked;
        bool mentorConfirmed;
        bool menteeConfirmed;
    }

    mapping(address mentee => mapping(address mentor => Session))
        internal s_sessions;

    error DEVMentor__TransferFailed();
    event RequestCancelled(address indexed mentee);
    event SessionCreated(
        address indexed mentee,
        address indexed mentor,
        uint256 engagement,
        uint256 valueLocked
    );
    event SessionValidated(address indexed mentee, address indexed mentor);
    event SessionRated(address indexed mentor, uint256 rating);
    event SessionCancelled(address indexed mentee, address indexed mentor);
    event SessionRefunded(
        address indexed mentee,
        address indexed mentor,
        uint256 amount
    );

    error DEVMentor__RequestAlreadyOpened(address _mentee);
    error DEVMentor__SessionDurationNotOver();
    error DEVMentor__MinimumEngagementNotReached();
    error DEVMentor__WrongRating();
    error DEVMentor__NotYourSession();
    error DEVMentor__CancellationTimeNotReached();

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

    constructor(
        string memory baseURI
    ) Ownable(msg.sender) RewardManager(baseURI) {}

    function updateSessionEngagement(
        address _mentee,
        address _mentor,
        uint256 _engagement
    ) external {
        s_sessions[_mentee][_mentor].engagement = _engagement;
    }

    function fulfillPendingRequests() external {
        if (s_menteeWithRequest.length > 0) {
            for (uint256 i = 0; i < s_menteeWithRequest.length; ++i) {
                address mentee = s_menteeWithRequest[i];
                Mentee storage menteeInfo = s_registeredMentees[mentee];
                MenteeRequest storage request = s_menteeRequests[mentee];
                address[] memory matchingMentors = getMatchingMentors(
                    request.learningSubject,
                    request.engagement,
                    menteeInfo.language
                );
                if (matchingMentors.length == 0) {
                    continue;
                } else {
                    menteeInfo.hasRequest = false;
                    s_menteeWithRequest[i] = s_menteeWithRequest[
                        s_menteeWithRequest.length - 1
                    ];
                    s_menteeWithRequest.pop();
                    if (i > 0) {
                        --i;
                    }
                    _matchMentorWithMentee(
                        matchingMentors[0],
                        mentee,
                        request.engagement,
                        0
                    );
                    delete s_menteeRequests[mentee];
                }
            }
        }
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

    function _validateSession(address _mentee, address _mentor) internal {
        Session storage session = s_sessions[_mentee][_mentor];
        if (session.startTime + session.engagement > block.timestamp) {
            revert DEVMentor__SessionDurationNotOver();
        }
        if (msg.sender == _mentee) {
            session.menteeConfirmed = true;
            emit MenteeConfirmedSession(_mentee, _mentor);
        } else {
            session.mentorConfirmed = true;
            emit MentorConfirmedSession(_mentee, _mentor);
        }
        if (session.menteeConfirmed && session.mentorConfirmed) {
            _completeSession(_mentor, _mentee, session.valueLocked);
            _mintXP(_mentee, session.engagement);
            _mintXP(_mentor, session.engagement);
            _mintMentorToken(_mentor, session.engagement);
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
        s_registeredMentors[_mentor].sessionCount++;
        s_registeredMentees[_mentee].sessionCount++;

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

    function _cancelSession(address _mentee, address _mentor) internal {
        Session storage session = s_sessions[_mentee][_mentor];
        if (session.mentee != _mentee || session.mentor != _mentor) {
            revert DEVMentor__NotYourSession();
        }
        if (
            block.timestamp < session.startTime + session.engagement + 1 weeks
        ) {
            revert DEVMentor__CancellationTimeNotReached();
        }
        if (
            (msg.sender == _mentee && !session.mentorConfirmed) ||
            (msg.sender == _mentor && !session.menteeConfirmed)
        ) {
            uint256 valueLocked = s_menteeLockedValue[_mentee];
            delete s_registeredMentees[_mentee].mentor;
            delete s_registeredMentors[_mentor].mentee;
            delete s_sessions[_mentee][_mentor];
            emit SessionCancelled(_mentee, _mentor);
            if (valueLocked > 0) {
                delete s_menteeLockedValue[_mentee];
                (bool success, ) = _mentee.call{value: valueLocked}("");
                if (!success) {
                    revert DEVMentor__TransferFailed();
                }
                emit SessionRefunded(_mentee, _mentor, valueLocked);
            }
        }
    }

    function getSession(
        address _mentee,
        address _mentor
    ) external view returns (Session memory) {
        return s_sessions[_mentee][_mentor];
    }
}
