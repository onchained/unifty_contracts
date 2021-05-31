pragma solidity ^0.5.17;

import "contracts/collections/Unifty.sol";
import "contracts/farms/UniftyFarm.sol";

contract UniftyFarmShopAddon is  Ownable, CloneFactory, WhitelistAdminRole {
	using SafeMath for uint256;
	
	address public nifAddress = address(0x1A186E7268F3Ed5AdFEa6B9e0655f70059941E11);
	address payable public feeAddress = address(0x2989018B83436C6bBa00144A8277fd859cdafA7D);
    uint256 public addonFee = 1000000000000000;
    uint256[] public wildcards;
    ERC1155Tradable public wildcardErc1155Address;
	bool public isCloned = false;
    address public farm;
    bool public constructed = false;
    // owner => farms
    mapping(address => address[]) public addons;
    // owner => farm => addon address
    mapping(address => address) public addon;
    
    uint256 public runMode = 0; // 0 = regular farming, turned off, 1 = farming + buyout, 2 = shop, only, no farming
    
    mapping(address => mapping( bytes => uint256 ) ) public prices;
    mapping(address => mapping( bytes => uint256 ) ) public artistPrices;
    
    bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;
    bytes4 constant internal ERC1155_RECEIVED_ERR_VALUE = 0x0;
    
    event NewShop(address indexed _user, address indexed _farmAddress, address indexed _shopAddress);
    
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'FarmShopAddon: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }
    

	constructor() public  {
	    
	    constructed = true;
		
	}
	
	function obtain(address _erc1155Address, uint256 _id, uint256 _amount) external lock payable {
	    
	    require(runMode == 1 || runMode == 2, "UniftyFarmShopAddon#obtain: Farm not open for direct sales.");
	    require(ERC1155Tradable(_erc1155Address).balanceOf(farm, _id) >= _amount, "UniftyFarmShopAddon#obtain: Desired amount exceeds stock.");
	    
	    bytes memory id = abi.encode(_id);
	    require(prices[_erc1155Address][id] != 0 || artistPrices[_erc1155Address][id] != 0, "UniftyFarmShopAddon#obtain: Price not set");
	    require(prices[_erc1155Address][id].add(artistPrices[_erc1155Address][id]).mul(_amount) == msg.value && msg.value > 0, "UniftyFarmShopAddon#obtain: Invalid value");
	    
	    (,,,,address _artist,,,,) = UniftyFarm(farm).cards(_erc1155Address, _id);
	    
	    if(address(_artist) != address(0)){
	        address(address(uint160(_artist))).transfer(artistPrices[_erc1155Address][id].mul(_amount));
	        address(address(uint160(UniftyFarm(farm).controller()))).transfer(prices[_erc1155Address][id].mul(_amount));
	    }else{
	        address(address(uint160(UniftyFarm(farm).controller()))).transfer(msg.value);
	    }
	    
	    UniftyFarm(address(farm)).removeNfts(_erc1155Address, _id, _amount, msg.sender);
	    
	}

	
	function getPrice(address _erc1155Address, uint256 _id) external view returns(uint256, uint256){
	    
	    return (prices[_erc1155Address][abi.encode(_id)], artistPrices[_erc1155Address][abi.encode(_id)]);
	}
	
	function hasAddon(address _farmAddress) external view returns(bool){
	    
	    return addon[_farmAddress] != address(0);
	}
	
	function getAddon(address _farmAddress) external view returns(address){
	    
	    return addon[_farmAddress];
	}
	
	function setPrice(address _erc1155Address, uint256 _id, uint256 _price, uint256 _artistPrice) external onlyWhitelistAdmin{
	    
	    prices[_erc1155Address][abi.encode(_id)] = _price;
	    artistPrices[_erc1155Address][abi.encode(_id)] = _artistPrice;
	}
	
	function setFarmStakePause(bool _paused) internal onlyWhitelistAdmin {
	    if(_paused && !UniftyFarm(address(farm)).paused()){
	        UniftyFarm(address(farm)).pause();
	    }else if(UniftyFarm(address(farm)).paused()){
	        UniftyFarm(address(farm)).unpause();
	    }
	}
	
	function setRunMode(uint256 _runMode) external onlyWhitelistAdmin {
	   runMode = _runMode;
	   
	   if(_runMode == 2){
	       setFarmStakePause(true);
	   }
	   else{
	       setFarmStakePause(false);
	   }
	}
	
	function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _amount, bytes calldata _data) external returns(bytes4){
	    
	    if(ERC1155Tradable(_operator) == ERC1155Tradable(address(this))){
	    
	        return ERC1155_RECEIVED_VALUE;
	    
	    }
	    
	    return ERC1155_RECEIVED_ERR_VALUE;
	}
	
	function onERC1155BatchReceived(address _operator, address _from, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external returns(bytes4){
	      
        if(ERC1155Tradable(_operator) == ERC1155Tradable(address(this))){
    
            return ERC1155_BATCH_RECEIVED_VALUE;
    
        }
    
        return ERC1155_RECEIVED_ERR_VALUE;
    }
	
	/**
	 * Cloning functions
	 * Disabled in clones and only working in the genesis contract.
	 * */
	 function init() external {
	    require(!constructed && !isCloned, "UniftyFarmShopAddon must not be constructed yet or cloned.");
	    
		super.initOwnable();
		super.initWhiteListAdmin();
		unlocked = 1;
		
	}
	
	 function newAddon(address _farmAddress) external lock payable returns(address){
	    
	    require(!isCloned, "FarmShopAddon#newAddon: Not callable from clone");
	    require(UniftyFarm(_farmAddress).owner() == msg.sender, "FarmShopAddon#newAddon: Not the farm owner");
	    
	    uint256 nifBalance = IERC20(nifAddress).balanceOf(msg.sender);
	    if(!iHaveAnyWildcard()){
	        require(msg.value == addonFee, "FarmShopAddon#newAddon: Invalid addon fee");
	    }
	    
	    address clone = createClone(address(this));
	    
	    UniftyFarmShopAddon(clone).init();
	    UniftyFarmShopAddon(clone).setFarm(_farmAddress);
	    UniftyFarmShopAddon(clone).setCloned();
	    UniftyFarmShopAddon(clone).addWhitelistAdmin(msg.sender);
	    UniftyFarmShopAddon(clone).renounceWhitelistAdmin();
	    UniftyFarmShopAddon(clone).transferOwnership(msg.sender);
	    
	    addons[msg.sender].push(clone);
	    addon[_farmAddress] = clone;
	    
	    // enough NIF or a wildcard? then there won't be no fee
	    if(!iHaveAnyWildcard()){
	        feeAddress.transfer(msg.value);
	    }
	    
	    emit NewShop(msg.sender, _farmAddress, clone);
	    
	    return clone;
	    
	}
	
	function iHaveAnyWildcard() public view returns (bool){
	    for(uint256 i = 0; i < wildcards.length; i++){
	        if(wildcardErc1155Address.balanceOf(msg.sender, wildcards[i]) > 0){
	            return true;
	        }
	    }
	  
	    return false;
	}
	
	function setNifAddress(address _nifAddress) external onlyWhitelistAdmin {
	    require(!isCloned, "FarmShopAddon#setNifAddress: Not callable from clone");
	    nifAddress = _nifAddress;
	}
	
	function setFeeAddress(address payable _feeAddress) external onlyWhitelistAdmin {
	    require(!isCloned, "FarmShopAddon#setFeeAddress: Not callable from clone");
	    feeAddress = _feeAddress;
	}
	
	function setAddonFee(uint256 _addonFee) external onlyWhitelistAdmin{
	    require(!isCloned, "FarmShopAddon#setAddonFee: Not callable from clone");
	    addonFee = _addonFee;
	}
	
	function setCloned() external onlyWhitelistAdmin {
	    require(!isCloned, "FarmShopAddon#setCloned: Not callable from clone");
	    isCloned = true;
	}
	
	function setFarm(address _farmAddress) external onlyWhitelistAdmin {
	    require(!isCloned, "FarmShopAddon#setFarm: Not callable from clone");
	    farm = _farmAddress;
	}
	
	function setWildcard(uint256 wildcard) external onlyWhitelistAdmin {
	    require(!isCloned, "FarmShopAddon#setWildcard: Not callable from clone");
	    wildcards.push(wildcard);
	}
	
	function setWildcardErc1155Address(ERC1155Tradable _address) external onlyWhitelistAdmin {
	    require(!isCloned, "FarmShopAddon#setWildcardErc1155Address: Not callable from clone");
	    wildcardErc1155Address = _address;
	}
	
	
	function removeWildcard(uint256 wildcard) external onlyWhitelistAdmin {
	    require(!isCloned, "FarmShopAddon#removeWildcard: Not callable from clone");
	    uint256 tmp = wildcards[wildcards.length - 1];
	    bool found = false;
	    for(uint256 i = 0; i < wildcards.length; i++){
	        if(wildcards[i] == wildcard){
	            wildcards[i] = tmp;
	            found = true;
	            break;
	        }
	    }
	    if(found){
	        delete wildcards[wildcards.length - 1];
	        wildcards.length--;
	    }
	}
}