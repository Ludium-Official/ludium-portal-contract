// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILdTimeLock
 * @dev Interface for time-lock operations and emergency functions
 */
interface ILdTimeLock {
    // Events
    event TimeLockOperationQueued(
        bytes32 indexed operationId,
        address indexed target,
        uint256 value,
        bytes data,
        uint256 executeAfter,
        string description
    );
    
    event TimeLockOperationExecuted(
        bytes32 indexed operationId,
        address indexed target,
        uint256 value,
        bytes data
    );
    
    event TimeLockOperationCancelled(bytes32 indexed operationId);
    
    // Structs
    struct TimeLockOperation {
        bytes32 operationId;
        address target;
        bool executed;
        bool cancelled;
        bytes data;
        uint256 value;
        uint256 executeAfter;
        string description;
    }
    
    // Functions
    function queueTimeLockOperation(
        address _target,
        uint256 _value,
        bytes memory _data,
        string memory _description
    ) external returns (bytes32);
    
    function executeTimeLockOperation(bytes32 _operationId) external;
    function cancelTimeLockOperation(bytes32 _operationId) external;
    
    function getTimeLockOperation(bytes32 _operationId) external view returns (
        address target,
        uint256 value,
        bytes memory data,
        uint256 executeAfter,
        bool executed,
        bool cancelled,
        string memory description
    );
}