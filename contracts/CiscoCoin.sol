//Moeda mais valorizada que BTC e ETH, confia...
//Aluno: FranCisco Camêlo
pragma solidity ^0.8.9;


contract CiscoCoin is ERC20PresetFixedSupply, AccessControlEnumerable {
    using Address for address;

   
    constructor() ERC20PresetFixedSupply("Cisco Coin", "CSC", 1000000000 * 10**decimals(), _msgSender()) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        console.log("contract created");
    }

    function withdraw(address payable to, uint256 amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "transfer to the zero address");
        require(amount <= payable(address(this)).balance, "You are trying to withdraw more funds than available");
        to.transfer(amount);
    }

    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }
}
