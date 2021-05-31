pragma solidity ^0.5.17;

import "contracts/lib/erc20/IERC20.sol";
import "contracts/lib/erc20/SafeERC20.sol";

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