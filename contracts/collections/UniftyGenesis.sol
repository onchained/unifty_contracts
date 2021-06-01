pragma solidity ^0.5.17;

import "contracts/lib/access/Ownable.sol";
import "contracts/lib/erc20/IERC20.sol";
import "contracts/lib/roles/WhitelistAdminRole.sol";
import "contracts/lib/clones/CloneFactory.sol";
import "contracts/lib/erc1155/ERC1155Tradable.sol";
import "contracts/collections/Unifty.sol";

contract UniftyGenesis is CloneFactory, Ownable, WhitelistAdminRole {
    ERC1155Tradable public erc1155;

    event PoolCreated(
        address indexed _user,
        address indexed _erc1155,
        uint256 _fee
    );

    mapping(address => address[]) internal pools; // 1st GenesisPool, 2nd ERC1155
    bool private constructed = false;
    bool private isCloned = false;

    address public nifAddress =
        address(0x3dF39266F1246128C39086E1b542Db0148A30d8c);
    address payable public feeAddress =
        address(0x4Ae96401dA3D541Bf426205Af3d6f5c969afA3DB);
    uint256 public poolFee = 150000000000000000;
    uint256 public poolFeeMinimumNif = 2500 * 10**18;
    uint256[] public wildcards;
    ERC1155Tradable public wildcardErc1155Address;

    function init(ERC1155Tradable _erc1155Address) public {
        require(
            !constructed && !isCloned,
            "UniftyGenesis must not be constructed yet or cloned."
        );
        constructed = true;
        erc1155 = _erc1155Address;
        super.initOwnable();
        super.initWhiteListAdmin();
    }

    constructor(ERC1155Tradable _erc1155Address) public {
        constructed = true;
        erc1155 = _erc1155Address;
    }

    function setNifAddress(address _nifAddress) external onlyWhitelistAdmin {
        require(!isCloned, "Not callable from clone");
        nifAddress = _nifAddress;
    }

    function setFeeAddress(address payable _feeAddress)
        external
        onlyWhitelistAdmin
    {
        require(!isCloned, "Not callable from clone");
        feeAddress = _feeAddress;
    }

    function setPoolFee(uint256 _poolFee) external onlyWhitelistAdmin {
        require(!isCloned, "Not callable from clone");
        poolFee = _poolFee;
    }

    function setPoolFeeMinimumNif(uint256 _minNif) external onlyWhitelistAdmin {
        require(!isCloned, "Not callable from clone");
        poolFeeMinimumNif = _minNif;
    }

    function setCloned() external onlyWhitelistAdmin {
        require(!isCloned, "Not callable from clone");
        isCloned = true;
    }

    function setWildcard(uint256 wildcard) external onlyWhitelistAdmin {
        require(!isCloned, "Not callable from clone");
        wildcards.push(wildcard);
    }

    function setWildcardErc1155Address(ERC1155Tradable _address)
        external
        onlyWhitelistAdmin
    {
        require(!isCloned, "Not callable from clone");
        wildcardErc1155Address = _address;
    }

    function removeWildcard(uint256 wildcard) external onlyWhitelistAdmin {
        require(!isCloned, "Not callable from clone");
        uint256 tmp = wildcards[wildcards.length - 1];
        bool found = false;
        for (uint256 i = 0; i < wildcards.length; i++) {
            if (wildcards[i] == wildcard) {
                wildcards[i] = tmp;
                found = true;
                break;
            }
        }
        if (found) {
            delete wildcards[wildcards.length - 1];
            wildcards.length--;
        }
    }

    function setErc1155(ERC1155Tradable _erc1155Address)
        external
        onlyWhitelistAdmin
    {
        erc1155 = _erc1155Address;
    }

    function newPool(
        string calldata _name,
        string calldata _symbol,
        string calldata _uri,
        string calldata _baseMetadataURI,
        address _proxyRegistryAddress
    ) external payable {
        require(!isCloned, "Not callable from clone");

        uint256 nifBalance = IERC20(nifAddress).balanceOf(msg.sender);
        if (nifBalance < poolFeeMinimumNif && !iHaveAnyWildcard()) {
            require(msg.value == poolFee, "Invalid pool fee");
        }

        address clone = createClone(address(erc1155));

        ERC1155Tradable(clone).init(_name, _symbol, _proxyRegistryAddress);

        ERC1155Tradable(clone).addWhitelistAdmin(msg.sender);
        ERC1155Tradable(clone).addMinter(msg.sender);

        Unifty(clone).setContractURI(_uri);
        Unifty(clone).setBaseMetadataURI(_baseMetadataURI);

        ERC1155Tradable(clone).renounceWhitelistAdmin();
        ERC1155Tradable(clone).renounceMinter();

        ERC1155Tradable(clone).transferOwnership(msg.sender);

        pools[msg.sender].push(clone);

        // enough NIF or a wildcard? then there won't be no fee
        if (nifBalance < poolFeeMinimumNif && !iHaveAnyWildcard()) {
            feeAddress.transfer(msg.value);
        }

        emit PoolCreated(
            msg.sender,
            clone,
            nifBalance < poolFeeMinimumNif && !iHaveAnyWildcard() ? poolFee : 0
        );
    }

    function iHaveAnyWildcard() public view returns (bool) {
        for (uint256 i = 0; i < wildcards.length; i++) {
            if (
                wildcardErc1155Address.balanceOf(msg.sender, wildcards[i]) > 0
            ) {
                return true;
            }
        }

        return false;
    }

    function getPool(address _address, uint256 index)
        external
        view
        returns (address)
    {
        require(!isCloned, "Not callable from clone");
        return pools[_address][index];
    }

    function getPoolsLength(address _address) external view returns (uint256) {
        require(!isCloned, "Not callable from clone");
        return pools[_address].length;
    }

    function getCurrentBlockNumber() public view returns (uint256) {
        return block.number;
    }
}
