// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

contract Languages {
    mapping(uint256 => string) public languages;
    uint256 private languagesCount;

    constructor(string[] memory _language) {
        for (uint i = 0; i < _language.length; i++) {
            languages[i] = _language[i];
            languagesCount++;
        }
    }

    function _addLanguage(string memory _language) internal {
        languages[languagesCount] = _language;
        languagesCount++;
    }

    function getLanguageById(
        uint256 _languageId
    ) public view returns (string memory) {
        return languages[_languageId];
    }

    function getAllLanguages() external view returns (string[] memory) {
        string[] memory allLanguages = new string[](languagesCount);
        for (uint i = 0; i < languagesCount; i++) {
            allLanguages[i] = languages[i];
        }
        return allLanguages;
    }
}
