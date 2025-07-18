// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/ILdTimeLock.sol";

/**
 * @title LdTimeLock
 * @dev Handles time-locked operations and emergency functions
 */
contract LdTimeLock is ILdTimeLock, Ownable, AccessControl, ReentrancyGuard {
    // Constants
    uint256 public constant TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours
    
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // State variables
    mapping(bytes32 => TimeLockOperation) public timeLockOperations;
    uint256 public nextOperationId;
    
    // Modifiers
    modifier onlyOwnerOrAdmin() {
        require(
            msg.sender == owner() || hasRole(ADMIN_ROLE, msg.sender),
            "Caller is not owner or admin"
        );
        _;
    }
    
    modifier onlyEmergencyRole() {
        require(hasRole(EMERGENCY_ROLE, msg.sender), "Caller does not have emergency role");
        _;
    }
    
    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ADMIN_ROLE, initialOwner);
        _grantRole(EMERGENCY_ROLE, initialOwner);
        
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, DEFAULT_ADMIN_ROLE);
    }
    
    /**
     * @dev Queue a time-locked operation
     */
    function queueTimeLockOperation(
        address _target,
        uint256 _value,
        bytes memory _data,
        string memory _description
    ) public onlyOwnerOrAdmin returns (bytes32) {
        bytes32 operationId = keccak256(
            abi.encode(_target, _value, _data, block.timestamp, nextOperationId++)
        );
        
        uint256 executeAfter = block.timestamp + TIMELOCK_DURATION;
        
        timeLockOperations[operationId] = TimeLockOperation({
            operationId: operationId,
            target: _target,
            data: _data,
            value: _value,
            executeAfter: executeAfter,
            executed: false,
            cancelled: false,
            description: _description
        });
        
        emit TimeLockOperationQueued(
            operationId,
            _target,
            _value,
            _data,
            executeAfter,
            _description
        );
        
        return operationId;
    }
    
    /**
     * @dev Execute a time-locked operation
     */
    function executeTimeLockOperation(
        bytes32 _operationId
    ) external onlyOwnerOrAdmin nonReentrant {
        TimeLockOperation storage operation = timeLockOperations[_operationId];
        
        require(operation.operationId != bytes32(0), "Operation does not exist");
        require(!operation.executed, "Operation already executed");
        require(!operation.cancelled, "Operation was cancelled");
        require(
            block.timestamp >= operation.executeAfter,
            "Operation still in time-lock period"
        );
        
        operation.executed = true;
        
        // Execute the operation
        (bool success, ) = operation.target.call{value: operation.value}(operation.data);
        require(success, "Time-locked operation execution failed");
        
        emit TimeLockOperationExecuted(
            _operationId,
            operation.target,
            operation.value,
            operation.data
        );
    }
    
    /**
     * @dev Cancel a time-locked operation
     */
    function cancelTimeLockOperation(
        bytes32 _operationId
    ) external onlyOwner {
        TimeLockOperation storage operation = timeLockOperations[_operationId];
        
        require(operation.operationId != bytes32(0), "Operation does not exist");
        require(!operation.executed, "Operation already executed");
        require(!operation.cancelled, "Operation already cancelled");
        
        operation.cancelled = true;
        
        emit TimeLockOperationCancelled(_operationId);
    }
    
    /**
     * @dev Get time-lock operation details
     */
    function getTimeLockOperation(
        bytes32 _operationId
    ) external view returns (
        address target,
        uint256 value,
        bytes memory data,
        uint256 executeAfter,
        bool executed,
        bool cancelled,
        string memory description
    ) {
        TimeLockOperation storage operation = timeLockOperations[_operationId];
        return (
            operation.target,
            operation.value,
            operation.data,
            operation.executeAfter,
            operation.executed,
            operation.cancelled,
            operation.description
        );
    }
    
    /**
     * @dev Queue emergency withdraw operation (requires time-lock)
     */
    function queueEmergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyEmergencyRole returns (bytes32) {
        bytes memory data = abi.encodeWithSignature(
            "_executeEmergencyWithdraw(address,uint256)",
            token,
            amount
        );
        
        string memory description = string(
            abi.encodePacked(
                "Emergency withdraw ",
                _uint2str(amount),
                " of token ",
                _addressToString(token)
            )
        );
        
        return queueTimeLockOperation(
            address(this),
            0,
            data,
            description
        );
    }
    
    /**
     * @dev Internal function to execute emergency withdraw
     */
    function _executeEmergencyWithdraw(
        address token,
        uint256 amount
    ) external {
        require(msg.sender == address(this), "Can only be called by timelock");
        
        if (token == address(0)) {
            // ETH withdrawal
            (bool sent, ) = payable(owner()).call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            // ERC20 withdrawal  
            // Note: This would need to be implemented with actual ERC20 transfer logic
            // For now, this is a placeholder
            revert("ERC20 emergency withdraw not implemented in timelock module");
        }
    }
    
    // Helper function to convert uint to string
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
    
    // Helper function to convert address to string
    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
    
    // Allow contract to receive ETH
    receive() external payable {}
}