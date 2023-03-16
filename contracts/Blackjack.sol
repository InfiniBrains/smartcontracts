pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Blackjack is Initializable, PausableUpgradeable, OwnableUpgradeable {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __Pausable_init();
        __Ownable_init();
        nonce = 0;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    uint256 nonce;
    // this function is exploitable. we need to change this ASAP
    function random() public returns (uint256) {
        uint256 randomNumber = uint256(
            keccak256(
                abi.encodePacked(
                    nonce,
                    msg.sender,
                    gasleft(),
                    block.difficulty,
                    block.timestamp,
                    block.number,
                    blockhash(block.number - 1),
                    block.coinbase,
                    block.gaslimit,
                    block.basefee,
                    block.chainid,
                    address(this)
                )
            )
        );
        nonce++;
        return randomNumber;
    }
}
