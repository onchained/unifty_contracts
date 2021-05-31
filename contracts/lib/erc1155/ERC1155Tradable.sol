pragma solidity ^0.5.17;

import "contracts/lib/erc1155/ERC1155.sol";
import "contracts/lib/erc1155/ERC1155MintBurn.sol";
import "contracts/lib/erc1155/ERC1155Metadata.sol";
import "contracts/lib/access/Ownable.sol";
import "contracts/lib/roles/MinterRole.sol";
import "contracts/lib/roles/WhitelistAdminRole.sol";
import "contracts/lib/utils/Strings.sol";

contract OwnableDelegateProxy {}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

/**
 * @title ERC1155Tradable
 * ERC1155Tradable - ERC1155 contract that whitelists an operator address, 
 * has create and mint functionality, and supports useful standards from OpenZeppelin,
  like _exists(), name(), symbol(), and totalSupply()
 */
contract ERC1155Tradable is
    ERC1155,
    ERC1155MintBurn,
    ERC1155Metadata,
    Ownable,
    MinterRole,
    WhitelistAdminRole
{
    using Strings for string;

    address proxyRegistryAddress;
    uint256 private _currentTokenID = 0;
    mapping(uint256 => address) public creators;
    mapping(uint256 => uint256) public tokenSupply;
    mapping(uint256 => uint256) public tokenMaxSupply;
    // Contract name
    string public name;
    // Contract symbol
    string public symbol;

    mapping(uint256 => string) private uris;

    bool private constructed = false;

    function init(
        string memory _name,
        string memory _symbol,
        address _proxyRegistryAddress
    ) public {
        require(!constructed, "ERC155 Tradeable must not be constructed yet");

        constructed = true;

        name = _name;
        symbol = _symbol;
        proxyRegistryAddress = _proxyRegistryAddress;

        super.initOwnable();
        super.initMinter();
        super.initWhiteListAdmin();
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _proxyRegistryAddress
    ) public {
        constructed = true;
        name = _name;
        symbol = _symbol;
        proxyRegistryAddress = _proxyRegistryAddress;
    }

    function removeWhitelistAdmin(address account) public onlyOwner {
        _removeWhitelistAdmin(account);
    }

    function removeMinter(address account) public onlyOwner {
        _removeMinter(account);
    }

    function uri(uint256 _id) public view returns (string memory) {
        require(_exists(_id), "ERC721Tradable#uri: NONEXISTENT_TOKEN");
        //return super.uri(_id);

        if (bytes(uris[_id]).length > 0) {
            return uris[_id];
        }
        return Strings.strConcat(baseMetadataURI, Strings.uint2str(_id));
    }

    /**
     * @dev Returns the total quantity for a token ID
     * @param _id uint256 ID of the token to query
     * @return amount of token in existence
     */
    function totalSupply(uint256 _id) public view returns (uint256) {
        return tokenSupply[_id];
    }

    /**
     * @dev Returns the max quantity for a token ID
     * @param _id uint256 ID of the token to query
     * @return amount of token in existence
     */
    function maxSupply(uint256 _id) public view returns (uint256) {
        return tokenMaxSupply[_id];
    }

    /**
     * @dev Will update the base URL of token's URI
     * @param _newBaseMetadataURI New base URL of token's URI
     */
    function setBaseMetadataURI(string memory _newBaseMetadataURI)
        public
        onlyWhitelistAdmin
    {
        _setBaseMetadataURI(_newBaseMetadataURI);
    }

    /**
     * @dev Creates a new token type and assigns _initialSupply to an address
     * @param _maxSupply max supply allowed
     * @param _initialSupply Optional amount to supply the first owner
     * @param _uri Optional URI for this token type
     * @param _data Optional data to pass if receiver is contract
     * @return The newly created token ID
     */
    function create(
        uint256 _maxSupply,
        uint256 _initialSupply,
        string calldata _uri,
        bytes calldata _data
    ) external onlyWhitelistAdmin returns (uint256 tokenId) {
        require(
            _initialSupply <= _maxSupply,
            "Initial supply cannot be more than max supply"
        );
        uint256 _id = _getNextTokenID();
        _incrementTokenTypeId();
        creators[_id] = msg.sender;

        if (bytes(_uri).length > 0) {
            uris[_id] = _uri;
            emit URI(_uri, _id);
        } else {
            emit URI(
                string(
                    abi.encodePacked(baseMetadataURI, _uint2str(_id), ".json")
                ),
                _id
            );
        }

        if (_initialSupply != 0) _mint(msg.sender, _id, _initialSupply, _data);
        tokenSupply[_id] = _initialSupply;
        tokenMaxSupply[_id] = _maxSupply;
        return _id;
    }

    function updateUri(uint256 _id, string calldata _uri)
        external
        onlyWhitelistAdmin
    {
        if (bytes(_uri).length > 0) {
            uris[_id] = _uri;
            emit URI(_uri, _id);
        } else {
            emit URI(
                string(
                    abi.encodePacked(baseMetadataURI, _uint2str(_id), ".json")
                ),
                _id
            );
        }
    }

    function burn(
        address _address,
        uint256 _id,
        uint256 _amount
    ) external {
        require(
            (msg.sender == _address) || isApprovedForAll(_address, msg.sender),
            "ERC1155#burn: INVALID_OPERATOR"
        );
        require(
            balances[_address][_id] >= _amount,
            "Trying to burn more tokens than you own"
        );
        _burn(_address, _id, _amount);
    }

    function updateProxyRegistryAddress(address _proxyRegistryAddress)
        external
        onlyWhitelistAdmin
    {
        require(_proxyRegistryAddress != address(0), "No zero address");
        proxyRegistryAddress = _proxyRegistryAddress;
    }

    /**
     * @dev Mints some amount of tokens to an address
     * @param _id          Token ID to mint
     * @param _quantity    Amount of tokens to mint
     * @param _data        Data to pass if receiver is contract
     */
    function mint(
        uint256 _id,
        uint256 _quantity,
        bytes memory _data
    ) public onlyMinter {
        uint256 tokenId = _id;
        require(
            tokenSupply[tokenId].add(_quantity) <= tokenMaxSupply[tokenId],
            "Max supply reached"
        );
        _mint(msg.sender, _id, _quantity, _data);
        tokenSupply[_id] = tokenSupply[_id].add(_quantity);
    }

    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-free listings.
     */

    function isApprovedForAll(address _owner, address _operator)
        public
        view
        returns (bool isOperator)
    {
        // Whitelist OpenSea proxy contract for easy trading.
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        if (address(proxyRegistry.proxies(_owner)) == _operator) {
            return true;
        }

        return ERC1155.isApprovedForAll(_owner, _operator);
    }

    /**
     * @dev Returns whether the specified token exists by checking to see if it has a creator
     * @param _id uint256 ID of the token to query the existence of
     * @return bool whether the token exists
     */
    function _exists(uint256 _id) internal view returns (bool) {
        return creators[_id] != address(0);
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenID
     * @return uint256 for the next token ID
     */
    function _getNextTokenID() private view returns (uint256) {
        return _currentTokenID.add(1);
    }

    /**
     * @dev increments the value of _currentTokenID
     */
    function _incrementTokenTypeId() private {
        _currentTokenID++;
    }
}
