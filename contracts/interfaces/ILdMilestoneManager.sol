// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILdMilestoneManager  
 * @dev Interface for milestone validation and management
 */
interface ILdMilestoneManager {
    // Events
    event MilestoneApproved(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        address indexed validator,
        uint256 approvalCount,
        uint256 requiredApprovals
    );
    
    event MilestoneCompleted(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        uint256 amount,
        address recipient
    );
    
    // Structs (for external consumption - no mappings)
    struct MilestoneData {
        string title;
        string description;
        uint256 deadline;
        uint16 percentage; // Basis points (10000 = 100%)
        uint16 approvalCount;
        bool isApproved;
        bool isCompleted;
    }
    
    // Functions
    function approveMilestone(uint256 _projectId, uint256 _milestoneIndex) external;
    function executeMilestone(uint256 _projectId, uint256 _milestoneIndex) external;
    
    function getMilestoneDetails(uint256 _projectId, uint256 _milestoneIndex) external view returns (
        string memory title,
        string memory description,
        uint256 percentage,
        uint256 deadline,
        bool isApproved,
        bool isCompleted,
        uint256 approvalCount
    );
    
    function getMilestoneCount(uint256 _projectId) external view returns (uint256);
}