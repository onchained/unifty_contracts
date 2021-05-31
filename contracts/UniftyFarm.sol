pragma solidity ^0.5.17;

import "./Unifty.sol";

contract PauserRole is Context {
    using Roles for Roles.Role;

    event PauserAdded(address indexed account);
    event PauserRemoved(address indexed account);

    Roles.Role private _pausers;

    function initPauserRole() internal{
        _addPauser(_msgSender());
    }

    constructor () internal {
        _addPauser(_msgSender());
    }

    modifier onlyPauser() {
        require(isPauser(_msgSender()), "PauserRole: caller does not have the Pauser role");
        _;
    }

    function isPauser(address account) public view returns (bool) {
        return _pausers.has(account);
    }

    function addPauser(address account) public onlyPauser {
        _addPauser(account);
    }

    function renouncePauser() public {
        _removePauser(_msgSender());
    }

    function _addPauser(address account) internal {
        _pausers.add(account);
        emit PauserAdded(account);
    }

    function _removePauser(address account) internal {
        _pausers.remove(account);
        emit PauserRemoved(account);
    }
}

contract Pausable is Context, PauserRole {

    event Paused(address account);
    event Unpaused(address account);
    bool private _paused;

    constructor () internal {
        _paused = false;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function pause() public onlyPauser whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function unpause() public onlyPauser whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

contract Wrap {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;
	IERC20 public token;

	constructor(IERC20 _tokenAddress) public {
		token = IERC20(_tokenAddress);
	}

	uint256 private _totalSupply;
	mapping(address => uint256) private _balances;

	function totalSupply() external view returns (uint256) {
		return _totalSupply;
	}

	function balanceOf(address account) public view returns (uint256) {
		return _balances[account];
	}

	function stake(uint256 amount) public {
		_totalSupply = _totalSupply.add(amount);
		_balances[msg.sender] = _balances[msg.sender].add(amount);
		IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
	}

	function withdraw(uint256 amount) public {
		_totalSupply = _totalSupply.sub(amount);
		_balances[msg.sender] = _balances[msg.sender].sub(amount);
		IERC20(token).safeTransfer(msg.sender, amount);
	}

	function _rescueScore(address account) internal {
		uint256 amount = _balances[account];

		_totalSupply = _totalSupply.sub(amount);
		_balances[account] = _balances[account].sub(amount);
		IERC20(token).safeTransfer(account, amount);
	}
}

interface DetailedERC20 {
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
}

contract UniftyFarm is Wrap, Ownable, Pausable, CloneFactory, WhitelistAdminRole {
	using SafeMath for uint256;

	struct Card {
		uint256 points;
		uint256 releaseTime;
		uint256 mintFee;
		uint256 controllerFee;
		address artist;
		address erc1155;
		bool nsfw;
		bool shadowed;
		uint256 supply;
	}
	
	address public nifAddress = address(0x3dF39266F1246128C39086E1b542Db0148A30d8c);
	address payable public feeAddress = address(0x4Ae96401dA3D541Bf426205Af3d6f5c969afA3DB);
    uint256 public farmFee = 1250000000000000000;
    uint256 public farmFeeMinimumNif = 5000 * 10**18;
    uint256[] public wildcards;
    ERC1155Tradable public wildcardErc1155Address;
	bool public isCloned = false;
    mapping(address => address[]) public farms;
    bool public constructed = false;
    
    bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;
    bytes4 constant internal ERC1155_RECEIVED_ERR_VALUE = 0x0;
    
	uint256 public periodStart;
	uint256 public minStake;
	uint256 public maxStake;
	uint256 public rewardRate = 86400; // 1 point per day per staked token, multiples of this lowers time per staked token
	uint256 public totalFeesCollected;
	uint256 public spentScore;
	address public rescuer;
	address public controller;

	mapping(address => uint256) public pendingWithdrawals;
	mapping(address => uint256) public lastUpdateTime;
	mapping(address => uint256) public points;
	mapping(address => mapping ( uint256 => Card ) ) public cards;

	event CardAdded(address indexed erc1155, uint256 indexed card, uint256 points, uint256 mintFee, address indexed artist, uint256 releaseTime);
	event CardType(address indexed erc1155, uint256 indexed card, string indexed cardType);
	event CardShadowed(address indexed erc1155, uint256 indexed card, bool indexed shadowed);
	event Removed(address indexed erc1155, uint256 indexed card, address indexed recipient, uint256 amount);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event Redeemed(address indexed user, address indexed erc1155, uint256 indexed id, uint256 amount);
	event RescueRedeemed(address indexed user, uint256 amount);
	event FarmCreated(address indexed user, address indexed farm, uint256 fee, string uri);
	event FarmUri(address indexed farm, string uri);

	modifier updateReward(address account) {
		if (account != address(0)) {
			points[account] = earned(account);
			lastUpdateTime[account] = block.timestamp;
		}
		_;
	}

	constructor(
		uint256 _periodStart,
		uint256 _minStake,
		uint256 _maxStake,
		address _controller,
		IERC20 _tokenAddress,
		string memory _uri
	) public Wrap(_tokenAddress) {
	    require(_minStake >= 0 && _maxStake > 0 && _maxStake >= _minStake, "Problem with min and max stake setup");
	    constructed = true;
		periodStart = _periodStart;
		minStake = _minStake;
		maxStake = _maxStake;
		controller = _controller;
		emit FarmCreated(msg.sender, address(this), 0, _uri);
	    emit FarmUri(address(this), _uri);
	}

	function cardMintFee(address erc1155Address, uint256 id) external view returns (uint256) {
		return cards[erc1155Address][id].mintFee.add(cards[erc1155Address][id].controllerFee);
	}

	function cardReleaseTime(address erc1155Address, uint256 id) external view returns (uint256) {
		return cards[erc1155Address][id].releaseTime;
	}

	function cardPoints(address erc1155Address, uint256 id) external view returns (uint256) {
		return cards[erc1155Address][id].points;
	}

	function earned(address account) public view returns (uint256) {
		
		uint256 decimals = DetailedERC20(address(token)).decimals();
		uint256 pow = 1;

        for(uint256 i = 0; i < decimals; i++){
            pow = pow.mul(10);
        }
		
		return points[account].add(
		    getCurrPoints(account, pow)
	    );
	}
	
	function getCurrPoints(address account, uint256 pow) internal view returns(uint256){
	    uint256 blockTime = block.timestamp;
	    return blockTime.sub(lastUpdateTime[account]).mul(pow).div(rewardRate).mul(balanceOf(account)).div(pow);
	}
	
	function setRewardRate(uint256 _rewardRate) external onlyWhitelistAdmin{
	    require(_rewardRate > 0, "Reward rate too low");
	    rewardRate = _rewardRate;
	}
	
	function setMinMaxStake(uint256 _minStake, uint256 _maxStake) external onlyWhitelistAdmin{
	    require(_minStake >= 0 && _maxStake > 0 && _maxStake >= _minStake, "Problem with min and max stake setup");
	    minStake = _minStake;
	    maxStake = _maxStake;
	}
	
	function stake(uint256 amount) public updateReward(msg.sender) whenNotPaused() {
		require(block.timestamp >= periodStart, "Pool not open");
		require(amount.add(balanceOf(msg.sender)) >= minStake && amount.add(balanceOf(msg.sender)) > 0, "Too few deposit");
		require(amount.add(balanceOf(msg.sender)) <= maxStake, "Deposit limit reached");

		super.stake(amount);
		emit Staked(msg.sender, amount);
	}

	function withdraw(uint256 amount) public updateReward(msg.sender) {
		require(amount > 0, "Cannot withdraw 0");

		super.withdraw(amount);
		emit Withdrawn(msg.sender, amount);
	}

	function exit() external {
		withdraw(balanceOf(msg.sender));
	}

	function redeem(address erc1155Address, uint256 id) external payable updateReward(msg.sender) {
		require(cards[erc1155Address][id].points != 0, "Card not found");
		require(block.timestamp >= cards[erc1155Address][id].releaseTime, "Card not released");
		require(points[msg.sender] >= cards[erc1155Address][id].points, "Redemption exceeds point balance");
		
		uint256 fees = cards[erc1155Address][id].mintFee.add( cards[erc1155Address][id].controllerFee );
		
        // wildcards and nif passes disabled in clones
        bool enableFees = fees > 0;
        
        if(!isCloned){
            uint256 nifBalance = IERC20(nifAddress).balanceOf(msg.sender);
            if(nifBalance >= farmFeeMinimumNif || iHaveAnyWildcard()){
                enableFees = false;
                fees = 0;
            }
        }
        
        require(msg.value == fees, "Send the proper ETH for the fees");

		if (enableFees) {
			totalFeesCollected = totalFeesCollected.add(fees);
			pendingWithdrawals[controller] = pendingWithdrawals[controller].add( cards[erc1155Address][id].controllerFee );
			pendingWithdrawals[cards[erc1155Address][id].artist] = pendingWithdrawals[cards[erc1155Address][id].artist].add( cards[erc1155Address][id].mintFee );
		}

		points[msg.sender] = points[msg.sender].sub(cards[erc1155Address][id].points);
		spentScore = spentScore.add(cards[erc1155Address][id].points);
		
		ERC1155Tradable(cards[erc1155Address][id].erc1155).safeTransferFrom(address(this), msg.sender, id, 1, "");
		
		emit Redeemed(msg.sender, cards[erc1155Address][id].erc1155, id, cards[erc1155Address][id].points);
	}

	function rescueScore(address account) external updateReward(account) returns (uint256) {
		require(msg.sender == rescuer, "!rescuer");
		uint256 earnedPoints = points[account];
		spentScore = spentScore.add(earnedPoints);
		points[account] = 0;

		if (balanceOf(account) > 0) {
			_rescueScore(account);
		}

		emit RescueRedeemed(account, earnedPoints);
		return earnedPoints;
	}

	function setController(address _controller) external onlyWhitelistAdmin {
		uint256 amount = pendingWithdrawals[controller];
		pendingWithdrawals[controller] = 0;
		pendingWithdrawals[_controller] = pendingWithdrawals[_controller].add(amount);
		controller = _controller;
	}

	function setRescuer(address _rescuer) external onlyWhitelistAdmin {
		rescuer = _rescuer;
	}

	function setControllerFee(address _erc1155Address, uint256 _id, uint256 _controllerFee) external onlyWhitelistAdmin {
		cards[_erc1155Address][_id].controllerFee = _controllerFee;
	}
	
	function setShadowed(address _erc1155Address, uint256 _id, bool _shadowed) external onlyWhitelistAdmin {
		cards[_erc1155Address][_id].shadowed = _shadowed;
		emit CardShadowed(_erc1155Address, _id, _shadowed);
	}
	
	function emitFarmUri(string calldata _uri) external onlyWhitelistAdmin{
	    emit FarmUri(address(this), _uri);
	} 
	
	function removeNfts(address _erc1155Address, uint256 _id, uint256 _amount, address _recipient) external onlyWhitelistAdmin{
	    
	    ERC1155Tradable(_erc1155Address).safeTransferFrom(address(this), _recipient, _id, _amount, "");
	    emit Removed(_erc1155Address, _id, _recipient, _amount);
	} 

	function createNft(
		uint256 _supply,
		uint256 _points,
		uint256 _mintFee,
		uint256 _controllerFee,
		address _artist,
		uint256 _releaseTime,
		address _erc1155Address,
		string calldata _uri,
		string calldata _cardType
	) external onlyWhitelistAdmin returns (uint256) {
		uint256 tokenId = ERC1155Tradable(_erc1155Address).create(_supply, _supply, _uri, "");
		require(tokenId > 0, "ERC1155 create did not succeed");
        Card storage c = cards[_erc1155Address][tokenId];
		c.points = _points;
		c.releaseTime = _releaseTime;
		c.mintFee = _mintFee;
		c.controllerFee = _controllerFee;
		c.artist = _artist;
		c.erc1155 = _erc1155Address;
		c.supply = _supply;
		emitCardAdded(_erc1155Address, tokenId, _points, _mintFee, _controllerFee, _artist, _releaseTime, _cardType);
		return tokenId;
	}
	
	function addNfts(
		uint256 _points,
		uint256 _mintFee,
		uint256 _controllerFee,
		address _artist,
		uint256 _releaseTime,
		address _erc1155Address,
		uint256 _tokenId,
		string calldata _cardType,
		uint256 _cardAmount
	) external onlyWhitelistAdmin returns (uint256) {
		require(_tokenId > 0, "Invalid token id");
		require(_cardAmount > 0, "Invalid card amount");
		Card storage c = cards[_erc1155Address][_tokenId];
		c.points = _points;
		c.releaseTime = _releaseTime;
		c.mintFee = _mintFee;
		c.controllerFee = _controllerFee;
		c.artist = _artist;
		c.erc1155 = _erc1155Address;
		c.supply = c.supply.add(_cardAmount);
		ERC1155Tradable(_erc1155Address).safeTransferFrom(msg.sender, address(this), _tokenId, _cardAmount, "");
		emitCardAdded(_erc1155Address, _tokenId, _points, _mintFee, _controllerFee, _artist, _releaseTime, _cardType);
		return _tokenId;
	}
	
	function updateNftData(
	    address _erc1155Address, 
	    uint256 _id,
	    uint256 _points,
		uint256 _mintFee,
		uint256 _controllerFee,
		address _artist,
		uint256 _releaseTime,
		bool _nsfw,
		bool _shadowed,
		string calldata _cardType
    ) external onlyWhitelistAdmin{
        require(_id > 0, "Invalid token id");
	    Card storage c = cards[_erc1155Address][_id];
		c.points = _points;
		c.releaseTime = _releaseTime;
		c.mintFee = _mintFee;
		c.controllerFee = _controllerFee;
		c.artist = _artist;
		c.nsfw = _nsfw;
		c.shadowed = _shadowed;
		emit CardType(_erc1155Address, _id, _cardType);
	}
	
	function supply(address _erc1155Address, uint256 _id) external view returns (uint256){
	    return cards[_erc1155Address][_id].supply;
	}
	
	function emitCardAdded(address _erc1155Address, uint256 tokenId, uint256 _points, uint256 _mintFee, uint256 _controllerFee, address _artist, uint256 _releaseTime, string memory _cardType) private onlyWhitelistAdmin{
	    emit CardAdded(_erc1155Address, tokenId, _points, _mintFee.add(_controllerFee), _artist, _releaseTime);
		emit CardType(_erc1155Address, tokenId, _cardType);
	}

	function withdrawFee() external {
		uint256 amount = pendingWithdrawals[msg.sender];
		require(amount > 0, "nothing to withdraw");
		pendingWithdrawals[msg.sender] = 0;
		msg.sender.transfer(amount);
	}
	
	function getFarmsLength(address _address) external view returns (uint256) {
	    return farms[_address].length;
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
	 function init( 
	    uint256 _periodStart,
	    uint256 _minStake,
		uint256 _maxStake,
		address _controller,
		IERC20 _tokenAddress,
		string calldata _uri,
		address _creator
	) external {
	    require(!constructed && !isCloned, "UniftyFarm must not be constructed yet or cloned.");
	    require(_minStake >= 0 && _maxStake > 0 && _maxStake >= _minStake, "Problem with min and max stake setup");
	    
	    rewardRate = 86400;
	    
	    periodStart = _periodStart;
	    minStake = _minStake;
		maxStake = _maxStake;
		controller = _controller;
		token = _tokenAddress;
	    
		super.initOwnable();
		super.initWhiteListAdmin();
		super.initPauserRole();
		
		emit FarmCreated(_creator, address(this), 0, _uri);
	    emit FarmUri(address(this), _uri);
	}
	
	 function newFarm(
	    uint256 _periodStart,
	    uint256 _minStake,
		uint256 _maxStake,
		address _controller,
		IERC20 _tokenAddress,
		string calldata _uri
    ) external payable {
	    
	    require(!isCloned, "Not callable from clone");
	    
	    uint256 nifBalance = IERC20(nifAddress).balanceOf(msg.sender);
	    if(nifBalance < farmFeeMinimumNif && !iHaveAnyWildcard()){
	        require(msg.value == farmFee, "Invalid farm fee");
	    }
	    
	    address clone = createClone(address(this));
	    
	    UniftyFarm(clone).init(_periodStart, _minStake, _maxStake, _controller, _tokenAddress, _uri, msg.sender);
	    UniftyFarm(clone).setCloned();
	    UniftyFarm(clone).addWhitelistAdmin(msg.sender);
	    UniftyFarm(clone).addPauser(msg.sender);
	    UniftyFarm(clone).renounceWhitelistAdmin();
	    UniftyFarm(clone).renouncePauser();
	    UniftyFarm(clone).transferOwnership(msg.sender);
	    
	    farms[msg.sender].push(clone);
	    
	    // enough NIF or a wildcard? then there won't be no fee
	    if(nifBalance < farmFeeMinimumNif && !iHaveAnyWildcard()){
	        feeAddress.transfer(msg.value);
	    }
	    
	    emit FarmCreated(msg.sender, clone, nifBalance < farmFeeMinimumNif && !iHaveAnyWildcard() ? farmFee : 0, _uri);
	    emit FarmUri(clone, _uri);
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
	    require(!isCloned, "Not callable from clone");
	    nifAddress = _nifAddress;
	}
	
	function setFeeAddress(address payable _feeAddress) external onlyWhitelistAdmin {
	    require(!isCloned, "Not callable from clone");
	    feeAddress = _feeAddress;
	}
	
	function setFarmFee(uint256 _farmFee) external onlyWhitelistAdmin{
	    require(!isCloned, "Not callable from clone");
	    farmFee = _farmFee;
	}
	
	function setFarmFeeMinimumNif(uint256 _minNif) external onlyWhitelistAdmin{
	    require(!isCloned, "Not callable from clone");
	    farmFeeMinimumNif = _minNif;
	}
	
	function setCloned() external onlyWhitelistAdmin {
	    require(!isCloned, "Not callable from clone");
	    isCloned = true;
	}
	
	function setWildcard(uint256 wildcard) external onlyWhitelistAdmin {
	    require(!isCloned, "Not callable from clone");
	    wildcards.push(wildcard);
	}
	
	function setWildcardErc1155Address(ERC1155Tradable _address) external onlyWhitelistAdmin {
	    require(!isCloned, "Not callable from clone");
	    wildcardErc1155Address = _address;
	}
	
	
	function removeWildcard(uint256 wildcard) external onlyWhitelistAdmin {
	    require(!isCloned, "Not callable from clone");
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