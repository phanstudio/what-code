// contracts/BurnManager.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IERC721Burnable {
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @title BurnManager
 * @dev Contract for managing NFT burns with payment system
 * Uses OpenZeppelin standards for security and access control
 */
contract BurnManager is Ownable, ReentrancyGuard, Pausable {
    using Address for address payable;

    address public immutable nftContract;
    uint256 private burnFee = 0.1 gwei;
    uint16 public burnAmount = 10;
    
    mapping(uint32 => bool) private isBurned;
    mapping(uint32 => bool) private isUpdated;
    
    uint256 private constant MAX_BURN_FEE = 1 ether;

    event TokensBurned(address indexed burner, uint32[] tokenIds, uint256 totalFee, uint32 indexed updateId);
    event BurnFeeUpdated(uint256 oldFee, uint256 newFee);
    event FundsWithdrawn(address indexed owner, uint256 amount);

    error InvalidTokenId();
    error InsufficientPayment();
    error TokenAlreadyBurned();
    error NotTokenOwner();
    error FeeExceedsMaximum();
    error FeeUnchanged();
    error NoFundsToWithdraw();
    error WithdrawalFailed();

    modifier validTokenId(uint256 tokenId) {
        if (tokenId == 0) revert InvalidTokenId();
        _;
    }

    constructor(address _nftContract) Ownable(msg.sender) {
        if (_nftContract == address(0)) revert InvalidTokenId();
        nftContract = _nftContract;
    }

    function createPremium(uint32[] calldata tokenIds, uint32 updateId)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        _validateInput(tokenIds, updateId);
        _processBurn(tokenIds, updateId);
        _refundExcess();
    }

    function _validateInput(uint32[] calldata tokenIds, uint32 updateId) private view {
        uint32 tokenCount = uint32(tokenIds.length);
        if (tokenCount == 0) revert("No tokens provided");
        if (tokenCount != burnAmount) revert("Burn the required token amount");

        if (msg.value < burnFee) revert("Insufficient payment");

        IERC721Burnable nft = IERC721Burnable(nftContract);

        if (nft.ownerOf(updateId) != msg.sender) revert("Not token owner");
        if (isBurned[updateId]) revert("Token already burned");
        if (isUpdated[updateId]) revert("Token already updated");

        for (uint32 i = 0; i < tokenCount; i++) {
            uint32 tokenId = tokenIds[i];
            if (tokenId == updateId) revert("updateId cannot be among tokenIds");
            if (isBurned[tokenId]) revert("Token already burned");
            if (nft.ownerOf(tokenId) != msg.sender) revert("Not token owner");
        }
    }

    function _processBurn(uint32[] calldata tokenIds, uint32 updateId) private {
        IERC721Burnable nft = IERC721Burnable(nftContract);

        isUpdated[updateId] = true;
        for (uint32 i = 0; i < tokenIds.length; i++) {
            uint32 tokenId = tokenIds[i];
            isBurned[tokenId] = true;
            nft.burn(tokenId);
        }

        emit TokensBurned(msg.sender, tokenIds, burnFee, updateId);
    }

    function _refundExcess() private {
        uint256 excess = msg.value - burnFee;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            if (!success) revert("Refund failed");
        }
    }

    function setBurnAmount(uint16 amount) external onlyOwner {
        require(amount > 0, "Minimum must be > 0");
        burnAmount = amount;
    }

    function isTokenBurned(uint32 tokenId) 
        external 
        view 
        validTokenId(tokenId) 
        returns (bool) 
    {
        return isBurned[tokenId];
    }

    function isUpdatedToken(uint32 tokenId) 
        external 
        view 
        validTokenId(tokenId) 
        returns (bool) 
    {
        return isUpdated[tokenId];
    }

    function setBurnFee(uint256 _newFee) external onlyOwner {
        if (_newFee > MAX_BURN_FEE) revert FeeExceedsMaximum();
        
        uint256 oldFee = burnFee;
        burnFee = _newFee;
        emit BurnFeeUpdated(oldFee, _newFee);
    }

    function _withdrawFunds(uint256 _amount) private nonReentrant {
        if (_amount == 0 || _amount > address(this).balance) revert NoFundsToWithdraw();

        payable(owner()).sendValue(_amount);
        emit FundsWithdrawn(owner(), _amount);
    }

    function withdrawFunds() external onlyOwner {
        _withdrawFunds(address(this).balance);
    }

    function withdrawPartialFunds(uint256 _amount) external onlyOwner {
        _withdrawFunds(_amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getBurnFee() external view returns (uint256) {
        return burnFee;
    }
    
    function getMaxBurnFee() external pure returns (uint256) {
        return MAX_BURN_FEE;
    }

    // Prevent accidental ETH sends
    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }
}