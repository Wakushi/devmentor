// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

contract SessionRegistry {
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

    modifier minimumEngagement(uint256 _engagement) {
        if (_engagement < 1 weeks) {
            revert DEVMentor__MinimumEngagementNotReached();
        }
        _;
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
