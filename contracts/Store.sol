// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

// contrato apenas para processar recebimento. a venda efetivamente acontece no mundo centralizado
// contrato deve receber em busd
// vender lootboxes
// user pode listar itens
// venda de lootboxes pode ser em game coin ou busd. porem lastreado em busd
// vender em BUSD e cobrar cut de marketplace

contract Store is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC1155ReceiverUpgradeable
{
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    struct Item {
        // token contract
        address tokenContract;
        // token id
        uint256 tokenId;
        // item title
        bytes32 title;
        // price in USD. Value is multiplied by 10**18.
        uint256 price;
    }

    struct SellVolume {
        uint256 date;
        uint256 amount;
    }

    // @dev the token the store accepts
    IERC20 public acceptedToken;

    // @dev the main dex pair
    IUniswapV2Pair internal _tknBnbPair;
    // @dev the pair to
    IUniswapV2Pair internal _bnbBusdPair;

    // @dev list of items available to sell
    Item[] public items;

    /**
     * @param _acceptedToken accepted ERC20 token address
     * @param tknBnb LP token address of TOKEN/BNB pair
     * @param bnbBusd LP token address of BNB/BUSD pair
     */
    function initialize(
        address _acceptedToken,
        address tknBnb,
        address bnbBusd
    ) public initializer {
        require(_acceptedToken.isContract(), "ERC20 token address must be a contract");
        require(tknBnb.isContract(), "TknBnbPair address must be a contract");
        require(bnbBusd.isContract(), "BnbBusdPair address must be a contract");

        acceptedToken = IERC20(_acceptedToken);
        _tknBnbPair = IUniswapV2Pair(tknBnb);
        _bnbBusdPair = IUniswapV2Pair(bnbBusd);

        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @dev Update the accepted token
     * @param addr of the token
     */
    function setAcceptedToken(address addr) external virtual onlyOwner {
        require(addr.isContract(), "ERC20 token address must be a contract");
        acceptedToken = IERC20(addr);

        emit AcceptedTokenChanged(addr);
    }


    /**
     * @dev Update the token bnb pair token
     * @param addr of the token
     */
    function setTknBnbPair(address addr) external virtual onlyOwner {
        require(addr.isContract(), "TknBnbPair address must be a contract");
        _tknBnbPair = IUniswapV2Pair(addr);

        emit TknBnbPairChanged(addr);
    }

    /**
     * @dev Update the bnb busd pair token
     * @param addr of the token
     */
    function setBnbBusdPair(address addr) external virtual onlyOwner {
        require(addr.isContract(), "BnbBusdPair address must be a contract");
        _bnbBusdPair = IUniswapV2Pair(addr);

        emit BnbBusdPairChanged(addr);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev pause the contract
     */
    function pause() external virtual onlyOwner {
        _pause();
    }

    /**
     * @dev unpause the contract
     */
    function unpause() external virtual onlyOwner {
        _unpause();
    }

    /**
     * @dev Add a new item.
     *  Can only be called by contract owner
     * @param tokenContract Address of ERC1155 inventory of items
     * @param tokenId of the ERC1155 contract. it is the item category.
     * @param title Item title name
     * @param price Price of the item
     */
    function addItemToBeSold(
        address tokenContract,
        uint256 tokenId,
        bytes32 title,
        uint256 price
    ) external virtual onlyOwner {
        require(tokenContract.isContract(), "NFT address must be a contract");
        require(price > 0, "Item price can't be 0");

        items.push(Item(tokenContract, tokenId, title, price));

        emit ItemAdded(tokenContract, items.length - 1, tokenId, title, price);
    }

    /**
     * @dev Remove an item
     *  When we delete an item, we move the last item to the deleted position
     * @param toDeleteIndex The array ID from items to be removed
     */
    function removeItemFromStore(uint256 toDeleteIndex) external virtual onlyOwner {
        require(toDeleteIndex < items.length, "Id should be between 0 and items length");

        Item memory toDelete = items[toDeleteIndex];

        uint256 lastIndex = items.length - 1;
        if (lastIndex != toDeleteIndex) {
            // Move the last value to the index where the value to delete is
            items[toDeleteIndex] = items[lastIndex];
        }

        // Delete the slot where the moved value was stored
        items.pop();

        emit ItemDeleted(toDeleteIndex, toDelete.tokenContract, toDelete.tokenId, toDelete.price);
    }

    /**
     * @dev list all items. to be used on the frontend
     */
    function listItems() external view returns (Item[] memory) {
        return items;
    }

    /**
     * @dev Update the price of an item.
     *  Can only be called by contract owner
     * @param id Id of the item
     * @param newPrice New price of the item
     */
    function updateItemPrice(uint256 id, uint256 newPrice) external virtual onlyOwner {
        require(id < items.length, "Item doesn't exists");
        require(newPrice != 0, "Item price can't be 0");

        Item storage item = items[id];

        item.price = newPrice;

        emit ItemPriceUpdated(id, newPrice);
    }

//    /**
//     * @dev Buy amounts of an item.
//     * @param id ID on items array
//     * @param title Item title name
//     * @param amounts Amounts of items to be sold
//     */
//    function buy1155Item(
//        uint256 id,
//        bytes32 title,
//        uint256 amounts
//    ) external virtual whenNotPaused nonReentrant {
//        require(amounts > 0, "Amounts must be greater than zero");
//        require(id < items.length, "Item doesn't exists");
//        Item memory item = items[id];
//        require(item.title == title, "Title argument must match requested item title");
//
//        address sender = _msgSender();
//
//        uint256 tknBusdPrice = getTKNtoBUSDprice();
//        uint256 itemPriceInToken = (item.price.mul(amounts).mul(10**18).div(tknBusdPrice));
//
//        uint256 allowance = acceptedToken.allowance(sender, address(this));
//        require(allowance >= itemPriceInToken, "Check the token allowance");
//
//        // Transfer item price amount to owner
//        require(
//            acceptedToken.transferFrom(sender, owner(), itemPriceInToken),
//            "Fail transferring the item price amount to owner"
//        );
//
//        IERC1155 nftRegistry = IERC1155(item.tokenContract);
//
//        nftRegistry.mint(sender, item.tokenId, amounts, "");
//
//        emit ItemBought(item.tokenContract, id, item.tokenId, owner(), sender, itemPriceInToken, amounts);
//    }

    function remove(SellVolume[] storage array, uint256 index) internal returns (bool success) {
        if (index >= array.length) return false;

        array[index] = array[array.length - 1];
        array.pop();

        return true;
    }

    /**
     * @dev Withdraw BNB from this contract
     * @param to receiver address
     * @param amount amount to withdraw
     */
    function withdraw(address payable to, uint256 amount) external virtual onlyOwner {
        require(to != address(0), "transfer to the zero address");
        require(amount <= payable(address(this)).balance, "You are trying to withdraw more funds than available");
        to.transfer(amount);
    }

    /**
     * @dev Withdraw any ERC20 token from this contract
     * @param tokenAddress ERC20 token to withdraw
     * @param to receiver address
     * @param amount amount to withdraw
     */
    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyOwner {
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }

    /**
     * @dev Withdraw any ERC721 token from this contract
     * @param tokenAddress ERC721 token to withdraw
     * @param to receiver address
     * @param tokenIds IDs of the NFTs to withdraw
     */
    function withdrawERC721(
        address tokenAddress,
        address to,
        uint256[] memory tokenIds
    ) external virtual onlyOwner {
        require(tokenIds.length <= 550, "You can withdraw at most 550 at a time");
        require(tokenAddress.isContract(), "ERC721 token address must be a contract");

        IERC721 tokenContract = IERC721(tokenAddress);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenContract.ownerOf(tokenIds[i]) == address(this),
                "Store doesn't own the NFT you are trying to withdraw"
            );

            tokenContract.safeTransferFrom(address(this), to, tokenIds[i]);
        }
    }

//    /**
//     * @dev Withdraw any ERC721 token from this contract
//     * @param tokenAddress ERC721 token to withdraw
//     * @param to receiver address
//     * @param amount amount to withdraw
//     */
//    function withdrawERC721(
//        address tokenAddress,
//        address to,
//        uint256 amount
//    ) external virtual onlyOwner {
//        require(amount <= 500, "You can withdraw at most 500 avatars at a time");
//        require(tokenAddress.isContract(), "ERC721 token address must be a contract");
//
//        IERC721 tokenContract = IERC721(tokenAddress);
//        uint256[] memory tokenIds = tokenContract.listMyNftIds();
//        require(tokenIds.length >= amount, "Store doesn't own the amount of NFTs");
//        for (uint256 i = 0; i < amount; i++) {
//            require(
//                tokenContract.ownerOf(tokenIds[i]) == address(this),
//                "Store doesn't own the NFT you are trying to withdraw"
//            );
//
//            tokenContract.safeTransferFrom(address(this), to, tokenIds[i]);
//        }
//    }

    /**
     * @dev Withdraw any ERC1155 token from this contract
     * @param tokenAddress ERC1155 token to withdraw
     * @param to receiver address
     * @param id ID of the token to withdraw
     * @param amount amount to withdraw
     */
    function withdrawERC1155(
        address tokenAddress,
        address to,
        uint256 id,
        uint256 amount
    ) external virtual onlyOwner {
        require(tokenAddress.isContract(), "ERC1155 token address must be a contract");

        IERC1155 tokenContract = IERC1155(tokenAddress);
        require(
            tokenContract.balanceOf(address(this), id) >= amount,
            "Store doesn't own the amount of tokens to withdraw"
        );

        tokenContract.safeTransferFrom(address(this), to, id, amount, "");
    }

    /**
     * @dev gets the price of TOKEN per BUSD.
     */
    function getTKNtoBUSDprice() public view virtual returns (uint256 price) {
        uint256 reserves0LP0 = 0;
        uint256 reserves1LP0 = 0;
        uint256 reserves0LP1 = 0;
        uint256 reserves1LP1 = 0;

        if (_tknBnbPair.token1() == _bnbBusdPair.token0()) {
            (reserves0LP0, reserves1LP0, ) = _tknBnbPair.getReserves();
            (reserves0LP1, reserves1LP1, ) = _bnbBusdPair.getReserves();

            return (reserves1LP1.mul(reserves1LP0).mul(10**18)).div(reserves0LP1.mul(reserves0LP0));
        } else if (_tknBnbPair.token1() == _bnbBusdPair.token1()) {
            (reserves0LP0, reserves1LP0, ) = _tknBnbPair.getReserves();
            (reserves1LP1, reserves0LP1, ) = _bnbBusdPair.getReserves();

            return (reserves1LP1.mul(reserves1LP0).mul(10**18)).div(reserves0LP1.mul(reserves0LP0));
        } else if (_tknBnbPair.token0() == _bnbBusdPair.token0()) {
            (reserves1LP0, reserves0LP0, ) = _tknBnbPair.getReserves();
            (reserves0LP1, reserves1LP1, ) = _bnbBusdPair.getReserves();

            return (reserves1LP1.mul(reserves1LP0).mul(10**18)).div(reserves0LP1.mul(reserves0LP0));
        } else {
            (reserves1LP0, reserves0LP0, ) = _tknBnbPair.getReserves();
            (reserves1LP1, reserves0LP1, ) = _bnbBusdPair.getReserves();

            return (reserves1LP1.mul(reserves1LP0).mul(10**18)).div(reserves0LP1.mul(reserves0LP0));
        }
    }

    /**
     * @dev gets the price in Token of an item.
     * @param id ID on items array
     * @param amounts Amounts of the items
     */
    function getItemPriceInToken(uint256 id, uint256 amounts) external view virtual returns (uint256 price) {
        require(amounts > 0, "Amounts must be greater than zero");
        require(id < items.length, "Item doesn't exists");
        Item memory item = items[id];

        uint256 tknBusdPrice = getTKNtoBUSDprice();

        return (item.price.mul(amounts).mul(10**18).div(tknBusdPrice));
    }

    /**
     * @dev upgradable version
     */
    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // MUST IMPLEMENT TO BE ABLE TO RECEIVE TOKENS
    receive() external payable {}

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // EVENTS
    event ItemAdded(address indexed tokenContract, uint256 id, uint256 tokenId, bytes32 title, uint256 price);
    event ItemDeleted(uint256 toDeleteIndex, address indexed tokenContract, uint256 itemId, uint256 price);
    event ItemPriceUpdated(uint256 id, uint256 price);
    event ItemBought(
        address indexed tokenContract,
        uint256 id,
        uint256 tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        uint256 amounts
    );
    event AcceptedTokenChanged(address indexed addr);
    event TknBnbPairChanged(address indexed addr);
    event BnbBusdPairChanged(address indexed addr);

    uint256[50] private __gap;
}