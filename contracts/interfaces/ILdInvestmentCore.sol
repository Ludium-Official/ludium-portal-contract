// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILdInvestmentCore
 * @dev Main interface for core investment program functionality
 */
interface ILdInvestmentCore {
    // Enums
    enum ProgramStatus { Ready, Active, Successful, Failed, Pending }
    enum ProjectStatus { Pending, Active, Successful, Failed, Cancelled }
    enum InvestmentCondition { Open, Tier }
    
    // Events  
    event InvestmentProgramCreated(
        uint256 indexed id,
        address indexed host,
        string name,
        uint256 maxFundingPerProject,
        address token
    );
    
    event ProjectValidated(
        uint256 indexed programId,
        uint256 indexed projectId,
        address indexed owner,
        string name,
        uint256 targetFunding
    );
    
    event ProgramStatusChanged(
        uint256 indexed programId,
        ProgramStatus oldStatus,
        ProgramStatus newStatus
    );
    
    event ProjectStatusChanged(
        uint256 indexed projectId,
        ProjectStatus oldStatus,
        ProjectStatus newStatus
    );
    
    event TokenWhitelisted(address indexed token, bool status);
    
    // Structs
    struct InvestmentProgram {
        uint256 id;
        string name;
        address host;
        address token;
        address[] validators;
        mapping(address => bool) validatorMapping;
        uint256 maxFundingPerProject;
        uint256 applicationStartTime;
        uint256 applicationEndTime;
        uint256 fundingStartTime;
        uint256 fundingEndTime;
        uint256 totalFeeCollected;
        uint256 projectCount;
        uint256 lastStatusUpdate;
        uint16 feePercentage;
        uint16 requiredApprovals;
        InvestmentCondition condition;
        ProgramStatus status;
        bool feeClaimed;
        bool statusCacheValid;
    }
    
    struct Project {
        uint256 id;
        uint256 programId;
        string name;
        address owner;
        ProjectStatus status;
        bool fundsReclaimed;
        uint256 targetFunding;
        uint256 totalInvested;
        uint256 supporterCount;
        uint256 termsCount;
        mapping(address => uint256) investments;
        mapping(uint256 => ProjectTerm) terms;
        mapping(address => mapping(uint256 => bool)) supporterTermClaims;
        mapping(address => UserTier) userTiers;
    }
    
    struct ProjectTerm {
        uint256 id;
        string title;
        string description;
        string benefits;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint32 purchaseLimit;
        uint32 currentPurchases;
        bool isActive;
    }
    
    struct UserTier {
        string tierName;
        uint256 maxInvestment;
        bool isAssigned;
    }
    
    // Functions
    function createInvestmentProgram(
        string memory _name,
        address[] memory _validators,
        uint256 _requiredApprovals,
        uint256 _maxFundingPerProject,
        uint256 _applicationStartTime,
        uint256 _applicationEndTime,
        uint256 _fundingStartTime,
        uint256 _fundingEndTime,
        InvestmentCondition _condition,
        uint256 _feePercentage,
        address _token
    ) external;
    
    struct MilestoneInput {
        string title;
        string description;
        uint256 percentage;
        uint256 deadline;
    }
    
    function signValidate(
        uint256 _programId,
        address _projectOwner,
        string memory _projectName,
        uint256 _targetFunding,
        MilestoneInput[] memory _milestones
    ) external;
    
    function getProgramDetails(uint256 _programId) external view returns (
        string memory name,
        address host,
        uint256 maxFundingPerProject,
        uint256 applicationStartTime,
        uint256 applicationEndTime,
        uint256 fundingStartTime,
        uint256 fundingEndTime,
        InvestmentCondition condition,
        uint256 feePercentage,
        ProgramStatus status,
        address token,
        bool feeClaimed
    );
    
    function getProjectDetails(uint256 _projectId) external view returns (
        string memory name,
        address owner,
        uint256 targetFunding,
        uint256 totalInvested,
        ProjectStatus status,
        uint256 programId
    );
    
    function getProgramStatus(uint256 _programId) external view returns (ProgramStatus);
    function setTokenWhitelist(address token, bool status) external;
}