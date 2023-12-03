// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FunctionsConsumer is FunctionsClient, Ownable {
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public donId;

    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    uint64 public s_subscriptionId;
    bytes public s_secretReference;

    uint32 public constant CALLBACK_GAS_LIMIT = 300000;

    constructor(
        address _router,
        bytes32 _donId
    ) FunctionsClient(_router) Ownable(msg.sender) {
        donId = _donId;
    }

    function setDonId(bytes32 newDonId) external onlyOwner {
        donId = newDonId;
    }

    function setCFSubId(uint64 _subscriptionId) external onlyOwner {
        s_subscriptionId = _subscriptionId;
    }

    function setSecretReference(
        bytes calldata _secretReference
    ) external onlyOwner {
        s_secretReference = _secretReference;
    }

    string source =
        "const url = 'https://devmentor-api-8206cc9733af.herokuapp.com/mailer';"
        "const apiResponse = await Functions.makeHttpRequest({"
        "url: url,"
        "method: 'POST',"
        "headers: {"
        "Authorization: `Bearer ${secrets.SECRET_KEY}`,"
        "'Content-Type': 'application/json',"
        "},"
        "data: {"
        "email: args[0],"
        "rewardId: args[1],"
        "uuid: args[2]"
        "},"
        "});"
        "if (apiResponse.error) {"
        "throw Error('Request failed');"
        "}"
        "const { data } = apiResponse;"
        "return Functions.encodeString(data.accepted);";

    /**
     * @notice Invokes a Chainlink Functions service to send an API request for emailing users.
     *         This function is called when a user burns or redeems their reward NFT to receive
     *         an official coupon or reduction code.
     * @dev  > Initializes a FunctionsRequest with JavaScript code and uses a DON-hosted location
     *         for secrets. Relies on an encrypted secret reference hosted on the DON, ensuring
     *         the server only accepts requests emitted from this contract. Stores the function ID
     *         of the last request after sending it.
     * @param args An array of arguments to be passed to the API call.
     *             These include the user's email, the reward ID, and an UUID to help the server
     *             batch node requests and only send one email per user.
     */
    function _sendMailerRequest(string[] calldata args) internal {
        FunctionsRequest.Request memory req;
        req.initializeRequest(
            FunctionsRequest.Location.Inline,
            FunctionsRequest.CodeLanguage.JavaScript,
            source
        );
        req.secretsLocation = FunctionsRequest.Location.DONHosted;
        req.encryptedSecretsReference = s_secretReference;
        if (args.length > 0) {
            req.setArgs(args);
        }
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            s_subscriptionId,
            CALLBACK_GAS_LIMIT,
            donId
        );
    }

    /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        s_lastResponse = response;
        s_lastError = err;
    }
}
