pragma solidity ^0.5.17;

import "contracts/lib/erc1155/ERC1155Tradable.sol";

/**
 * @title Unifty
 * Unifty - NFT Tools
 *
 * Rinkeby Opensea: 0xf57b2c51ded3a29e6891aba85459d600256cf317
 * Mainnet Opensea: 0xa5409ec958c83c3f309868babaca7c86dcb077c1
 */
contract Unifty is ERC1155Tradable {
    string private _contractURI = "https://unifty.io/meta/contract.json";

    constructor(address _proxyRegistryAddress)
        public
        ERC1155Tradable("Unifty", "UNIF", _proxyRegistryAddress)
    {
        _setBaseMetadataURI("https://unifty.io/meta/");
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory _uri) public onlyWhitelistAdmin {
        _contractURI = _uri;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
