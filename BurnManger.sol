// contracts/BurnManager.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    uint256 private burnFee = 0.0000001 ether;
    uint16 public burnAmount = 10;
    
    mapping(uint32 => bool) private isBurned;
    mapping(uint32 => bool) private isUpdated;
    
    // Maximum fee limit to prevent owner abuse
    uint256 private constant MAX_BURN_FEE = 0.1 ether;

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

    // function createPremium(uint32[] calldata tokenIds, uint32 update_id)
    //     external
    //     payable
    //     nonReentrant
    //     whenNotPaused
    // {
    //     uint256 totalFee = burnFee;
    //     if (msg.value < totalFee) revert InsufficientPayment();
    //     if (tokenIds.length != burnAmount) revert("Burn the required token amount");

    //     IERC721Burnable nft = IERC721Burnable(nftContract);
        
    //     // Validate all tokens first
    //     for (uint256 i = 0; i < tokenIds.length; i++) {
    //         uint32 tokenId = tokenIds[i];
    //         if (tokenId == update_id) revert("update_id cannot be among tokenIds");
    //         if (isBurned[tokenId]) revert TokenAlreadyBurned();
    //         if (nft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
    //     }

    //     // Handle refund before state changes
    //     uint256 excess = msg.value - totalFee;
    //     if (excess > 0) {
    //         (bool success, ) = payable(msg.sender).call{value: excess}("");
    //         if (!success) revert("Refund failed");
    //     }

    //     // Now make state changes
    //     isUpdated[update_id] = true;
    //     for (uint32 i = 0; i < tokenIds.length; i++) {
    //         uint32 tokenId = tokenIds[i];
    //         isBurned[tokenId] = true;
    //         nft.burn(tokenId);
    //     }
    //     emit TokensBurned(msg.sender, tokenIds, totalFee, update_id);
    // }

    // function createPremium(uint32[] calldata tokenIds, uint32 update_id)
    //     external
    //     payable
    //     nonReentrant
    //     whenNotPaused
    // {
    //     uint32 tokenCount = uint32(tokenIds.length);
    //     if (tokenCount != burnAmount) revert("Burn the required token amount");
    //     if (tokenCount == 0) revert("No tokens provided");
        
    //     uint256 totalFee = burnFee;
    //     if (msg.value < totalFee) revert InsufficientPayment();

    //     IERC721Burnable nft = IERC721Burnable(nftContract);
        
    //     // Validate update_id first
    //     if (nft.ownerOf(update_id) != msg.sender) revert NotTokenOwner();
    //     if (isBurned[update_id]) revert TokenAlreadyBurned();
    //     if (isUpdated[update_id]) revert("Token already updated");
        
    //     // Validate all tokens in a single loop
    //     for (uint32 i = 0; i < tokenCount; i++) {
    //         uint32 tokenId = tokenIds[i];
    //         if (tokenId == update_id) revert("update_id cannot be among tokenIds");
    //         if (isBurned[tokenId]) revert TokenAlreadyBurned();
    //         if (nft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
    //     }

    //     // STATE CHANGES (Effects)
    //     isUpdated[update_id] = true;
    //     for (uint32 i = 0; i < tokenCount; i++) {
    //         uint32 tokenId = tokenIds[i];
    //         isBurned[tokenId] = true;
    //         nft.burn(tokenId);
    //     }
        
    //     // EXTERNAL INTERACTIONS (Interactions)
    //     emit TokensBurned(msg.sender, tokenIds, totalFee, update_id);
        
    //     // Handle refund last
    //     uint256 excess = msg.value - totalFee;
    //     if (excess > 0) {
    //         (bool success, ) = payable(msg.sender).call{value: excess}("");
    //         if (!success) revert("Refund failed");
    //     }
    // }

    function createPremium(uint32[] calldata tokenIds, uint32 update_id)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        uint32 tokenCount = uint32(tokenIds.length);
        if (tokenCount == 0) revert("No tokens provided");
        if (tokenCount != burnAmount) revert("Burn the required token amount");

        uint256 totalFee = burnFee;
        if (msg.value < totalFee) revert("Insufficient payment");

        IERC721Burnable nft = IERC721Burnable(nftContract);

        // Validate update_id first
        if (nft.ownerOf(update_id) != msg.sender) revert("Not token owner");
        if (isBurned[update_id]) revert("Token already burned");
        if (isUpdated[update_id]) revert("Token already updated");

        // Validate all tokens in a single loop
        for (uint32 i = 0; i < tokenCount; i++) {
            uint32 tokenId = tokenIds[i];
            if (tokenId == update_id) revert("update_id cannot be among tokenIds");
            if (isBurned[tokenId]) revert("Token already burned");
            if (nft.ownerOf(tokenId) != msg.sender) revert("Not token owner");
        }

        // STATE CHANGES (Effects)
        isUpdated[update_id] = true;
        for (uint32 i = 0; i < tokenCount; i++) {
            uint32 tokenId = tokenIds[i];
            isBurned[tokenId] = true;
            nft.burn(tokenId);
        }

        // EXTERNAL INTERACTIONS (Interactions)
        emit TokensBurned(msg.sender, tokenIds, totalFee, update_id);

        // Handle refund last
        uint256 excess = msg.value - totalFee;
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

    function withdrawFunds() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFundsToWithdraw();
        
        payable(owner()).sendValue(balance);
        emit FundsWithdrawn(owner(), balance);
    }

    function withdrawPartialFunds(uint256 _amount) external onlyOwner nonReentrant {
        if (_amount == 0 || _amount > address(this).balance) revert NoFundsToWithdraw();
        
        payable(owner()).sendValue(_amount);
        emit FundsWithdrawn(owner(), _amount);
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