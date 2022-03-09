// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

abstract contract ERC20Base is ERC20Burnable, ERC20Snapshot, ERC20Permit, Pausable, AccessControlEnumerable {
	using SafeMath for uint256;
	using Address for address;

	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

	uint8 private _decimals;

	bool public trading = false;

	mapping(address => bool) public isExcludedFromFees;
	mapping(address => bool) public isBlacklisted;

	constructor(string memory name, string memory symbol, uint256 totalSupply, uint8 tokenDecimals) ERC20(name, symbol) ERC20Permit(name) {
		excludeFromFees(address(this), true);
		excludeFromFees(_msgSender(), true);

		_mint(_msgSender(), totalSupply);
		_decimals = tokenDecimals;
	}

	function pause() public onlyRole(PAUSER_ROLE) {
		_pause();
	}

	function unpause() public onlyRole(PAUSER_ROLE) {
		_unpause();
	}

	function _beforeTokenTransfer(address from, address to, uint256 amount)
		internal virtual override(ERC20, ERC20Snapshot)
	{
		super._beforeTokenTransfer(from, to, amount);

		require(from != address(0), "ERC20: transfer from the zero address");
		require(to != address(0), "ERC20: transfer to the zero address");
		require(amount > 0, "Transfer amount must be greater than zero");

		require(!isBlacklisted[from], "Address is blacklisted");
		require(trading || (isExcludedFromFees[from] || isExcludedFromFees[to]), "Trading not started");
	}

	receive() external payable {}

	function decimals() public view override returns (uint8) {
		return _decimals;
	}

	function setTrading(bool _enable) public onlyRole(MANAGER_ROLE) {
		trading = _enable;
		emit TradingEnabled(_enable);
	}

	function excludeFromFees(address account, bool excluded) public onlyRole(MANAGER_ROLE) {
		require(isExcludedFromFees[account] != excluded, "Already excluded");
		isExcludedFromFees[account] = excluded;

		emit ExcludeFromFees(account, excluded);
	}

	function blacklistAccount(address account, bool blacklisted) external onlyRole(MANAGER_ROLE) {
		require(isBlacklisted[account] != blacklisted, "Already blacklisted");
		isBlacklisted[account] = blacklisted;

		emit AccountBlacklisted(account, blacklisted);
	}

	event TradingEnabled(bool indexed enabled);
	event ExcludeFromFees(address indexed account, bool indexed isExcluded);
	event AccountBlacklisted(address indexed account, bool indexed isBlacklisted);
}
