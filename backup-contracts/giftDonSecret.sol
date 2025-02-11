// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC721} from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.5/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.5/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract GetGift is FunctionsClient, ERC721URIStorage {
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    string public result;
    mapping(address => bool) private allowList;
    mapping(string => bool) private giftCodeRedeemed;
    mapping(bytes32 => address) private reqIdToAddr;
    mapping(bytes32 => string) private reqIdToGiftCode;
    uint256 public tokenId;

    error UnexpectedRequestID(bytes32 requestId);

    event Response(bytes32 indexed requestId, bytes response, bytes err);

    // Gift codes and NFT metadata (saved on IPFS)
    mapping (bytes => string) giftToTokenUri;
    bytes ITEM_1 = bytes("100 discount");
    bytes ITEM_2 = bytes("50 discount");
    bytes ITEM_3 = bytes("1-month premium");

    string constant ITEM_1_METADATA = "ipfs://QmaGqBNqHazCjSMNMuDk6VrgjNLMQKNZqaab1vfMHAwkoj";
    string constant ITEM_2_METADATA = "ipfs://QmfNhhpUezQLcyqXBGL4ehPwo7Gfbwk9yy3YcJqGgr9dPb";
    string constant ITEM_3_METADATA = "ipfs://QmNxq7GqehZf9SpCEFK7C4moxZTZPNwCer5yCAqCBNdk2a";

    // Hardcode for Avalanche Fuji testnet
    address public constant ROUTER_ADDR = 0xA9d587a00A31A52Ed70D6026794a8FC5E2F5dCb0;
    bytes32 public constant DON_ID = 0x66756e2d6176616c616e6368652d66756a692d31000000000000000000000000;
    uint32 public constant CALLBACK_GAS_LIMIT = 300_000;
    
    // Hardcode javascript code that is to sent to DON
    // REPLACE THE SUPBASE PROJECT NAME in js code below:
    // "url: `https://<SUPBASE_PROJECT_NAME>.supabase.co/rest/v1/<TABLE_NAME>?select=<COLUMN_NAME1>,<COLUMN_NAME2>`,"
    // TABLE_NAME is the name of table created in step 1.
    // COLUMN_NAMES are names of columns to be search, in the case, they are gift_code and gift_name.
    string public constant SOURCE = 
        "const giftCode = args[0];"
        "if(!secrets.apikey) { throw Error(\"Error: Supabase API Key is not set!\") };"
        "const apikey = secrets.apikey;"
        "const apiResponse = await Functions.makeHttpRequest({"
            "url: \"https://hetiqdhzuhgeedeqdmmb.supabase.co/rest/v1/Gifts?select=gift_name,gift_code\","
            "method: \"GET\","
            "headers: { \"apikey\": apikey,}"
        "});"

        "if (apiResponse.error) {"
            "console.error(apiResponse.error);"
            "throw Error(\"Request failed\");"
        "};"

        "const { data } = apiResponse;"
        "const item = data.find(item => item.gift_code == giftCode);"
        
        "if(item == undefined) {return Functions.encodeString(\"not found\")};"
        "return Functions.encodeString(item.gift_name);";


    constructor() FunctionsClient(ROUTER_ADDR) ERC721("Gift", "GT"){
        allowList[msg.sender] = true;
        giftToTokenUri[ITEM_1] = ITEM_1_METADATA;
        giftToTokenUri[ITEM_2] = ITEM_2_METADATA;
        giftToTokenUri[ITEM_3] = ITEM_3_METADATA;
    }

    /**
     * @notice Send a simple request
     * @param subscriptionId Billing ID
     */
    function sendRequest(
        // bytes memory encryptedSecretsUrls,
        uint8 donHostedSecretsSlotID,
        uint64 donHostedSecretsVersion,
        string[] memory args,
        uint64 subscriptionId,
        address userAddr
    ) external onlyAllowList returns (bytes32 requestId) {
        // make sure the code is not used
        string memory giftCode = args[0];
        require(!giftCodeRedeemed[giftCode], "the code is redeemed");

        // send the Chainlink Functions request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(SOURCE);
        // if (encryptedSecretsUrls.length > 0)
        //     req.addSecretsReference(encryptedSecretsUrls);
        if (donHostedSecretsVersion > 0) 
            req.addDONHostedSecrets(
                donHostedSecretsSlotID,
                donHostedSecretsVersion
            );
        if (args.length > 0) req.setArgs(args);
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            CALLBACK_GAS_LIMIT,
            DON_ID
        );

        // mark the code as redeemed
        // redeemed[giftCode] = true;
        reqIdToAddr[s_lastRequestId] = userAddr;
        reqIdToGiftCode[s_lastRequestId] = giftCode;
        return s_lastRequestId;
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
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        s_lastResponse = response;
        s_lastError = err;

        emit Response(requestId, s_lastResponse, s_lastError);

        // check if the code is valid, incorrected code returns empty string
        if(keccak256(response) == keccak256(bytes("not found"))) return;
        
        // response is not empty, giftCode is valid
        address userAddr = reqIdToAddr[requestId];
        string memory tokenUri = giftToTokenUri[response];
        safeMint(userAddr, tokenUri);
        
        // mark gift code is redeemed
        // please be noticed that gift can only be redeemed once
        string memory giftCode = reqIdToGiftCode[requestId];
        giftCodeRedeemed[giftCode] = true;
    }

    function safeMint(address to, string memory uri) internal {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        tokenId++;
    }

    function addGift(string memory giftName, string memory _tokenUri) public onlyAllowList {
        giftToTokenUri[bytes(giftName)] = _tokenUri;
    }

    function addToAllowList(address addrToAdd) external onlyAllowList {
        allowList[addrToAdd] = true;
    }

    function removeFromAllowList() external onlyAllowList {
        allowList[msg.sender] = false;
    }

    modifier onlyAllowList(){
        require(allowList[msg.sender], "you do not have permission to call the function");
        _;
    }
}