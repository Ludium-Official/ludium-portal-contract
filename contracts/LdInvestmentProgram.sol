// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract LdInvestmentProgram is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Events
    event InvestmentProgramCreated(
        uint256 indexed programId,
        address indexed host,
        string name,
        uint256 maxFundingPerProject,
        address token
    );

    event ProjectCreated(
        uint256 indexed projectId,
        uint256 indexed programId,
        address indexed owner,
        string name,
        uint256 fundingTarget
    );

    event ProjectValidated(
        uint256 indexed projectId,
        address indexed validator,
        uint256 approvalCount,
        uint256 requiredApprovals
    );

    event InvestmentMade(
        uint256 indexed projectId,
        address indexed supporter,
        uint256 amount,
        uint256 totalFunded
    );

    event MilestoneAccepted(
        uint256 indexed projectId,
        uint256 indexed milestoneId,
        address indexed projectOwner,
        uint256 amount
    );

    event FundsReclaimed(
        uint256 indexed projectId,
        address indexed supporter,
        uint256 amount
    );

    event FeeClaimed(
        uint256 indexed programId,
        address indexed host,
        uint256 amount
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

    event MilestoneAdded(
        uint256 indexed projectId,
        uint256 indexed milestoneId,
        string title,
        uint256 percentage,
        uint256 deadline
    );

    event TierAssigned(
        uint256 indexed projectId,
        address indexed user,
        string tierName,
        uint256 maxInvestment
    );

    event ProgramUpdated(
        uint256 indexed programId,
        string name,
        uint256 maxFundingPerProject,
        uint256 applicationStartTime,
        uint256 applicationEndTime,
        uint256 fundingStartTime,
        uint256 fundingEndTime
    );

    event ProjectUpdated(
        uint256 indexed projectId,
        string name,
        uint256 fundingTarget
    );

    event EmergencyPaused(address account);
    event EmergencyUnpaused(address account);

    // Enums
    enum ProgramStatus {
        Ready, // Before applications start
        ApplicationOngoing, // Accepting project applications
        ApplicationClosed, // Applications closed but funding not started
        FundingOngoing, // Investment period
        ProjectOngoing, // Projects in progress
        ProgramCompleted // All projects completed or failed
    }

    enum ProjectStatus {
        Ready, // Before funding start
        FundingOngoing, // Investment period
        ProjectOngoing, // Project in progress (funding successful)
        ProjectFailed, // Funding failed or milestone missed
        ProjectCompleted // All milestones completed
    }

    enum InvestmentCondition {
        Open, // No restrictions
        Tier // Tier-based restrictions
    }

    // Structures
    struct InvestmentProgram {
        uint256 id;
        string name;
        address host;
        address[] validators; // Keep array but add mapping for O(1) lookup
        mapping(address => bool) validatorMapping; // O(1) validator lookup
        uint256 requiredApprovals;
        uint256 maxFundingPerProject;
        uint256 applicationStartTime;
        uint256 applicationEndTime;
        uint256 fundingStartTime;
        uint256 fundingEndTime;
        InvestmentCondition condition;
        uint256 feePercentage; // Fee percentage (default 300 = 3%)
        ProgramStatus status;
        address token;
        bool feeClaimed;
        uint256 totalFeeCollected;
        mapping(uint256 => uint256) projectIds; // Array of project IDs in this program
        uint256 projectCount;
        // Gas optimization: Cache status and only recalculate when needed
        uint256 lastStatusUpdate;
        bool statusCacheValid;
    }

    struct Project {
        uint256 id;
        uint256 programId;
        address owner;
        string name;
        uint256 fundingTarget;
        uint256 totalFunded;
        uint256 approvalCount;
        mapping(address => bool) validatorApprovals;
        ProjectStatus status;
        mapping(address => uint256) supporters; // supporter address => amount invested
        address[] supporterList; // List of all supporters
        uint256 milestoneCount;
        mapping(uint256 => Milestone) milestones; // milestone ID => milestone
        uint256 totalPaidOut;
        bool fundingSuccessful;
        uint256 createdAt;
        mapping(address => TierInfo) tierAssignments; // user address => tier info
        // Gas optimization: Cache failed milestone check
        bool hasFailedMilestone;
        uint256 lastMilestoneCheck;
    }

    struct Milestone {
        uint256 id;
        string title;
        string description;
        uint256 percentage; // Percentage of total funding (e.g., 2500 = 25%)
        uint256 deadline;
        bool completed;
        bool paid;
        uint256 amount; // Calculated amount based on percentage
    }

    struct TierInfo {
        string tierName;
        uint256 maxInvestment;
        bool isAssigned;
    }

    struct ValidationRequest {
        uint256 projectId;
        address projectOwner;
        string projectName;
        uint256 fundingTarget;
        uint256 timestamp;
        bool processed;
    }

    struct MilestoneData {
        string title;
        string description;
        uint256 percentage;
        uint256 deadline;
    }

    // State variables
    mapping(uint256 => InvestmentProgram) public investmentPrograms;
    mapping(uint256 => Project) public projects;
    mapping(uint256 => ValidationRequest) public validationRequests;
    mapping(address => bool) public whitelistedTokens;

    uint256 public nextProgramId;
    uint256 public nextProjectId;
    uint256 public nextValidationRequestId;
    uint256 private defaultFeePercentage = 300; // 3%

    // ETH address constant
    address public constant ETH_ADDRESS = address(0);

    // Circuit breaker thresholds
    uint256 public constant MAX_VALIDATORS_PER_PROGRAM = 50; // Prevent excessive gas costs
    uint256 public constant MAX_MILESTONES_PER_PROJECT = 20; // Prevent excessive gas costs

    // Modifiers
    modifier onlyProgramHost(uint256 programId) {
        require(
            investmentPrograms[programId].host == msg.sender,
            "Not program host"
        );
        _;
    }

    modifier onlyProjectOwner(uint256 projectId) {
        require(projects[projectId].owner == msg.sender, "Not project owner");
        _;
    }

    // Gas optimized validator modifier using mapping instead of loop
    modifier onlyValidator(uint256 programId) {
        require(
            investmentPrograms[programId].validatorMapping[msg.sender],
            "Not a validator"
        );
        _;
    }

    modifier validProgram(uint256 programId) {
        require(programId < nextProgramId, "Program does not exist");
        _;
    }

    modifier validProject(uint256 projectId) {
        require(projectId < nextProjectId, "Project does not exist");
        _;
    }

    // Circuit breaker modifier
    modifier withinGasLimits(uint256 validatorCount, uint256 milestoneCount) {
        require(
            validatorCount <= MAX_VALIDATORS_PER_PROGRAM,
            "Too many validators"
        );
        require(
            milestoneCount <= MAX_MILESTONES_PER_PROJECT,
            "Too many milestones"
        );
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {
        whitelistedTokens[ETH_ADDRESS] = true;
    }

    // Emergency pause function
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }

    // ===== CORE PROGRAM MANAGEMENT FUNCTIONS =====

    /**
     * @dev Creates a new investment program with gas optimization
     */
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
    ) external whenNotPaused withinGasLimits(_validators.length, 0) {
        require(bytes(_name).length > 0, "Program name cannot be empty");
        require(_validators.length > 0, "At least one validator required");
        require(
            _requiredApprovals > 0 && _requiredApprovals <= _validators.length,
            "Invalid approval count"
        );
        require(
            _maxFundingPerProject > 0,
            "Max funding must be greater than 0"
        );
        require(
            _applicationStartTime > block.timestamp,
            "Application start time must be in future"
        );
        require(
            _applicationEndTime > _applicationStartTime,
            "Invalid application time range"
        );
        require(
            _fundingStartTime >= _applicationEndTime,
            "Funding start must be after application end"
        );
        require(
            _fundingEndTime > _fundingStartTime,
            "Invalid funding time range"
        );
        require(_feePercentage <= 1000, "Fee percentage too high"); // Max 10%
        require(whitelistedTokens[_token], "Token not whitelisted");

        uint256 programId = nextProgramId++;

        InvestmentProgram storage program = investmentPrograms[programId];
        program.id = programId;
        program.name = _name;
        program.host = msg.sender;
        program.requiredApprovals = _requiredApprovals;
        program.maxFundingPerProject = _maxFundingPerProject;
        program.applicationStartTime = _applicationStartTime;
        program.applicationEndTime = _applicationEndTime;
        program.fundingStartTime = _fundingStartTime;
        program.fundingEndTime = _fundingEndTime;
        program.condition = _condition;
        program.feePercentage = _feePercentage > 0
            ? _feePercentage
            : defaultFeePercentage;
        program.status = ProgramStatus.Ready;
        program.token = _token;
        program.feeClaimed = false;
        program.totalFeeCollected = 0;
        program.projectCount = 0;
        program.lastStatusUpdate = block.timestamp;
        program.statusCacheValid = true;

        // Gas optimized validator setup
        program.validators = _validators;
        for (uint256 i = 0; i < _validators.length; i++) {
            require(_validators[i] != address(0), "Invalid validator address");
            program.validatorMapping[_validators[i]] = true;
        }

        emit InvestmentProgramCreated(
            programId,
            msg.sender,
            _name,
            _maxFundingPerProject,
            _token
        );
    }

    /**
     * @dev Get validator count (gas optimized)
     */
    function getValidatorCount(
        uint256 _programId
    ) external view validProgram(_programId) returns (uint256) {
        return investmentPrograms[_programId].validators.length;
    }

    /**
     * @dev Get validator at index (gas optimized)
     */
    function getValidatorAt(
        uint256 _programId,
        uint256 _index
    ) external view validProgram(_programId) returns (address) {
        require(
            _index < investmentPrograms[_programId].validators.length,
            "Index out of bounds"
        );
        return investmentPrograms[_programId].validators[_index];
    }

    /**
     * @dev Get all validators (use with caution for large sets)
     */
    function getAllValidators(
        uint256 _programId
    ) external view validProgram(_programId) returns (address[] memory) {
        return investmentPrograms[_programId].validators;
    }

    /**
     * @dev Updates an existing investment program (only host can update)
     * @param _programId Program ID to update
     * @param _name New program name
     * @param _maxFundingPerProject New max funding per project
     * @param _applicationStartTime New application start time
     * @param _applicationEndTime New application end time
     * @param _fundingStartTime New funding start time
     * @param _fundingEndTime New funding end time
     * @param _feePercentage New fee percentage
     */
    function updateProgram(
        uint256 _programId,
        string memory _name,
        uint256 _maxFundingPerProject,
        uint256 _applicationStartTime,
        uint256 _applicationEndTime,
        uint256 _fundingStartTime,
        uint256 _fundingEndTime,
        uint256 _feePercentage
    )
        external
        validProgram(_programId)
        onlyProgramHost(_programId)
        whenNotPaused
    {
        InvestmentProgram storage program = investmentPrograms[_programId];

        // Only allow updates before application period starts
        require(
            block.timestamp < program.applicationStartTime,
            "Cannot update after applications start"
        );

        require(bytes(_name).length > 0, "Program name cannot be empty");
        require(
            _maxFundingPerProject > 0,
            "Max funding must be greater than 0"
        );
        require(
            _applicationStartTime > block.timestamp,
            "Application start time must be in future"
        );
        require(
            _applicationEndTime > _applicationStartTime,
            "Invalid application time range"
        );
        require(
            _fundingStartTime >= _applicationEndTime,
            "Funding start must be after application end"
        );
        require(
            _fundingEndTime > _fundingStartTime,
            "Invalid funding time range"
        );
        require(_feePercentage <= 1000, "Fee percentage too high");

        program.name = _name;
        program.maxFundingPerProject = _maxFundingPerProject;
        program.applicationStartTime = _applicationStartTime;
        program.applicationEndTime = _applicationEndTime;
        program.fundingStartTime = _fundingStartTime;
        program.fundingEndTime = _fundingEndTime;
        program.feePercentage = _feePercentage;

        // Invalidate status cache since times changed
        program.statusCacheValid = false;

        emit ProgramUpdated(
            _programId,
            _name,
            _maxFundingPerProject,
            _applicationStartTime,
            _applicationEndTime,
            _fundingStartTime,
            _fundingEndTime
        );
    }

    /**
     * @dev Adds a milestone to a project with gas limits
     * @param _projectId Project ID
     * @param _title Milestone title
     * @param _description Milestone description
     * @param _percentage Percentage of total funding for this milestone
     * @param _deadline Milestone deadline
     */
    function addMilestone(
        uint256 _projectId,
        string memory _title,
        string memory _description,
        uint256 _percentage,
        uint256 _deadline
    )
        external
        validProject(_projectId)
        onlyProjectOwner(_projectId)
        whenNotPaused
    {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        require(
            project.milestoneCount < MAX_MILESTONES_PER_PROJECT,
            "Too many milestones"
        );
        require(
            block.timestamp < program.fundingStartTime,
            "Cannot add milestones after funding starts"
        );
        require(bytes(_title).length > 0, "Milestone title cannot be empty");
        require(_percentage > 0 && _percentage <= 10000, "Invalid percentage"); // Max 100%
        require(
            _deadline > program.fundingEndTime,
            "Milestone deadline must be after funding ends"
        );

        uint256 milestoneId = project.milestoneCount++;

        Milestone storage milestone = project.milestones[milestoneId];
        milestone.id = milestoneId;
        milestone.title = _title;
        milestone.description = _description;
        milestone.percentage = _percentage;
        milestone.deadline = _deadline;
        milestone.completed = false;
        milestone.paid = false;
        milestone.amount = 0; // Will be calculated when funding is successful

        emit MilestoneAdded(
            _projectId,
            milestoneId,
            _title,
            _percentage,
            _deadline
        );
    }

    /**
     * @dev Sets tier information for a user in a project
     * @param _projectId Project ID
     * @param _user User address
     * @param _tierName Tier name
     * @param _maxInvestment Maximum investment amount for this tier
     */
    function setProjectTier(
        uint256 _projectId,
        address _user,
        string memory _tierName,
        uint256 _maxInvestment
    )
        external
        validProject(_projectId)
        onlyProjectOwner(_projectId)
        whenNotPaused
    {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        require(
            program.condition == InvestmentCondition.Tier,
            "Program does not use tier system"
        );
        require(_user != address(0), "Invalid user address");
        require(bytes(_tierName).length > 0, "Tier name cannot be empty");
        require(_maxInvestment > 0, "Max investment must be greater than 0");

        project.tierAssignments[_user] = TierInfo({
            tierName: _tierName,
            maxInvestment: _maxInvestment,
            isAssigned: true
        });

        emit TierAssigned(_projectId, _user, _tierName, _maxInvestment);
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * @dev Gets investment program details
     * @param _programId Program ID
     * @return id Program ID
     * @return name Program name
     * @return host Program host address
     * @return validators Array of validator addresses
     * @return requiredApprovals Number of required approvals
     * @return maxFundingPerProject Maximum funding per project
     * @return applicationStartTime Application start timestamp
     * @return applicationEndTime Application end timestamp
     * @return fundingStartTime Funding start timestamp
     * @return fundingEndTime Funding end timestamp
     * @return condition Investment condition
     * @return feePercentage Fee percentage
     * @return status Program status
     * @return token Token address
     * @return feeClaimed Whether fee has been claimed
     * @return projectCount Number of projects in program
     */
    function getProgramDetails(
        uint256 _programId
    )
        external
        view
        validProgram(_programId)
        returns (
            uint256 id,
            string memory name,
            address host,
            address[] memory validators,
            uint256 requiredApprovals,
            uint256 maxFundingPerProject,
            uint256 applicationStartTime,
            uint256 applicationEndTime,
            uint256 fundingStartTime,
            uint256 fundingEndTime,
            InvestmentCondition condition,
            uint256 feePercentage,
            ProgramStatus status,
            address token,
            bool feeClaimed,
            uint256 projectCount
        )
    {
        InvestmentProgram storage program = investmentPrograms[_programId];
        return (
            program.id,
            program.name,
            program.host,
            program.validators,
            program.requiredApprovals,
            program.maxFundingPerProject,
            program.applicationStartTime,
            program.applicationEndTime,
            program.fundingStartTime,
            program.fundingEndTime,
            program.condition,
            program.feePercentage,
            getProgramStatus(_programId),
            program.token,
            program.feeClaimed,
            program.projectCount
        );
    }

    /**
     * @dev Gets project details
     * @param _projectId Project ID
     * @return id Project ID
     * @return programId Program ID
     * @return owner Project owner address
     * @return name Project name
     * @return fundingTarget Funding target amount
     * @return totalFunded Total amount funded
     * @return approvalCount Number of validator approvals
     * @return status Project status
     * @return milestoneCount Number of milestones
     * @return totalPaidOut Total amount paid out
     * @return fundingSuccessful Whether funding was successful
     * @return createdAt Creation timestamp
     */
    function getProjectDetails(
        uint256 _projectId
    )
        external
        view
        validProject(_projectId)
        returns (
            uint256 id,
            uint256 programId,
            address owner,
            string memory name,
            uint256 fundingTarget,
            uint256 totalFunded,
            uint256 approvalCount,
            ProjectStatus status,
            uint256 milestoneCount,
            uint256 totalPaidOut,
            bool fundingSuccessful,
            uint256 createdAt
        )
    {
        Project storage project = projects[_projectId];
        return (
            project.id,
            project.programId,
            project.owner,
            project.name,
            project.fundingTarget,
            project.totalFunded,
            project.approvalCount,
            getProjectStatus(_projectId),
            project.milestoneCount,
            project.totalPaidOut,
            project.fundingSuccessful,
            project.createdAt
        );
    }

    /**
     * @dev Gets milestone details
     * @param _projectId Project ID
     * @param _milestoneId Milestone ID
     * @return id Milestone ID
     * @return title Milestone title
     * @return description Milestone description
     * @return percentage Percentage of total funding
     * @return deadline Milestone deadline
     * @return completed Whether milestone is completed
     * @return paid Whether milestone is paid
     * @return amount Milestone amount
     */
    function getMilestoneDetails(
        uint256 _projectId,
        uint256 _milestoneId
    )
        external
        view
        validProject(_projectId)
        returns (
            uint256 id,
            string memory title,
            string memory description,
            uint256 percentage,
            uint256 deadline,
            bool completed,
            bool paid,
            uint256 amount
        )
    {
        Project storage project = projects[_projectId];
        require(
            _milestoneId < project.milestoneCount,
            "Milestone does not exist"
        );

        Milestone storage milestone = project.milestones[_milestoneId];
        return (
            milestone.id,
            milestone.title,
            milestone.description,
            milestone.percentage,
            milestone.deadline,
            milestone.completed,
            milestone.paid,
            milestone.amount
        );
    }

    /**
     * @dev Gets user's tier information for a project
     * @param _projectId Project ID
     * @param _user User address
     * @return tierName Tier name
     * @return maxInvestment Maximum investment amount
     * @return isAssigned Whether tier is assigned
     */
    function getUserTierInfo(
        uint256 _projectId,
        address _user
    )
        external
        view
        validProject(_projectId)
        returns (string memory tierName, uint256 maxInvestment, bool isAssigned)
    {
        Project storage project = projects[_projectId];
        TierInfo storage tierInfo = project.tierAssignments[_user];
        return (tierInfo.tierName, tierInfo.maxInvestment, tierInfo.isAssigned);
    }

    /**
     * @dev Gets user's investment amount in a project
     * @param _projectId Project ID
     * @param _user User address
     * @return Investment amount
     */
    function getUserInvestment(
        uint256 _projectId,
        address _user
    ) external view validProject(_projectId) returns (uint256) {
        return projects[_projectId].supporters[_user];
    }

    /**
     * @dev Gets list of all supporters for a project
     * @param _projectId Project ID
     * @return Array of supporter addresses
     */
    function getProjectSupporters(
        uint256 _projectId
    ) external view validProject(_projectId) returns (address[] memory) {
        return projects[_projectId].supporterList;
    }

    /**
     * @dev Gets list of project IDs in a program
     * @param _programId Program ID
     * @return Array of project IDs
     */
    function getProgramProjects(
        uint256 _programId
    ) external view validProgram(_programId) returns (uint256[] memory) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        uint256[] memory projectIds = new uint256[](program.projectCount);

        for (uint256 i = 0; i < program.projectCount; i++) {
            projectIds[i] = program.projectIds[i];
        }

        return projectIds;
    }

    // Token whitelist management
    function setTokenWhitelist(address token, bool status) external onlyOwner {
        whitelistedTokens[token] = status;
        emit TokenWhitelisted(token, status);
    }

    // Get program status based on current time and conditions
    function getProgramStatus(
        uint256 programId
    ) public view validProgram(programId) returns (ProgramStatus) {
        InvestmentProgram storage program = investmentPrograms[programId];

        // Use cached status if valid and not too old (1 hour)
        if (
            program.statusCacheValid &&
            block.timestamp < program.lastStatusUpdate + 1 hours
        ) {
            return program.status;
        }

        uint256 currentTime = block.timestamp;

        // Check if manually set to completed
        if (program.status == ProgramStatus.ProgramCompleted) {
            return ProgramStatus.ProgramCompleted;
        }

        // Time-based status determination
        if (currentTime < program.applicationStartTime) {
            return ProgramStatus.Ready;
        } else if (
            currentTime >= program.applicationStartTime &&
            currentTime <= program.applicationEndTime
        ) {
            return ProgramStatus.ApplicationOngoing;
        } else if (
            currentTime > program.applicationEndTime &&
            currentTime < program.fundingStartTime
        ) {
            return ProgramStatus.ApplicationClosed;
        } else if (
            currentTime >= program.fundingStartTime &&
            currentTime <= program.fundingEndTime
        ) {
            return ProgramStatus.FundingOngoing;
        } else if (currentTime > program.fundingEndTime) {
            // For post-funding, we need to check projects but this is expensive
            // In practice, this should be called less frequently
            return _calculatePostFundingStatus(programId);
        }

        return program.status;
    }

    /**
     * @dev Calculate post-funding status (expensive operation)
     */
    function _calculatePostFundingStatus(
        uint256 programId
    ) internal view returns (ProgramStatus) {
        InvestmentProgram storage program = investmentPrograms[programId];

        // Check if there are any ongoing projects
        bool hasOngoingProjects = false;
        for (uint256 i = 0; i < program.projectCount; i++) {
            uint256 projectId = program.projectIds[i];
            ProjectStatus projectStatus = getProjectStatus(projectId);
            if (
                projectStatus == ProjectStatus.ProjectOngoing ||
                projectStatus == ProjectStatus.FundingOngoing
            ) {
                hasOngoingProjects = true;
                break;
            }
        }

        if (hasOngoingProjects) {
            return ProgramStatus.ProjectOngoing;
        } else {
            return ProgramStatus.ProgramCompleted;
        }
    }

    // Get project status based on current time and conditions
    function getProjectStatus(
        uint256 projectId
    ) public view validProject(projectId) returns (ProjectStatus) {
        Project storage project = projects[projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];
        uint256 currentTime = block.timestamp;

        // Check if manually set to failed or completed
        if (
            project.status == ProjectStatus.ProjectFailed ||
            project.status == ProjectStatus.ProjectCompleted
        ) {
            return project.status;
        }

        // Time-based status determination
        if (currentTime < program.fundingStartTime) {
            return ProjectStatus.Ready;
        } else if (
            currentTime >= program.fundingStartTime &&
            currentTime <= program.fundingEndTime
        ) {
            return ProjectStatus.FundingOngoing;
        } else if (currentTime > program.fundingEndTime) {
            // Check if funding target was met
            if (project.totalFunded >= project.fundingTarget) {
                // Use cached milestone check if available and recent
                if (
                    project.hasFailedMilestone &&
                    block.timestamp < project.lastMilestoneCheck + 1 hours
                ) {
                    return ProjectStatus.ProjectFailed;
                }

                // For detailed milestone checking, this is expensive
                // In practice, checkMilestoneDeadline should be called periodically
                return _calculateProjectMilestoneStatus(projectId);
            } else {
                return ProjectStatus.ProjectFailed;
            }
        }

        return project.status;
    }

    /**
     * @dev Calculate project milestone status (expensive operation)
     */
    function _calculateProjectMilestoneStatus(
        uint256 projectId
    ) internal view returns (ProjectStatus) {
        Project storage project = projects[projectId];
        uint256 currentTime = block.timestamp;

        // Check if any milestone deadlines have passed without completion
        bool hasExpiredMilestones = false;
        for (uint256 i = 0; i < project.milestoneCount; i++) {
            Milestone storage milestone = project.milestones[i];
            if (!milestone.completed && currentTime > milestone.deadline) {
                hasExpiredMilestones = true;
                break;
            }
        }

        if (hasExpiredMilestones) {
            return ProjectStatus.ProjectFailed;
        }

        // Check if all milestones are completed
        bool allMilestonesCompleted = true;
        for (uint256 i = 0; i < project.milestoneCount; i++) {
            if (!project.milestones[i].completed) {
                allMilestonesCompleted = false;
                break;
            }
        }

        if (allMilestonesCompleted) {
            return ProjectStatus.ProjectCompleted;
        } else {
            return ProjectStatus.ProjectOngoing;
        }
    }

    // Helper function to check if an address is in an array
    function _contains(
        address[] memory array,
        address addr
    ) private pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == addr) {
                return true;
            }
        }
        return false;
    }

    // Set default fee percentage
    function setDefaultFeePercentage(
        uint256 _feePercentage
    ) external onlyOwner {
        require(_feePercentage <= 1000, "Fee percentage too high"); // Max 10%
        defaultFeePercentage = _feePercentage;
    }

    // Get default fee percentage
    function getDefaultFeePercentage() external view returns (uint256) {
        return defaultFeePercentage;
    }

    // Emergency functions
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == ETH_ADDRESS) {
            (bool sent, ) = payable(owner()).call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    function getContractBalance(address token) external view returns (uint256) {
        if (token == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    // Events that were referenced but not defined above
    event TokenWhitelisted(address token, bool status);

    // ===== VALIDATOR & PROJECT FUNCTIONS =====

    /**
     * @dev Validators sign to approve a project application
     * @param _programId Program ID
     * @param _projectOwner Project owner address
     * @param _projectName Project name
     * @param _fundingTarget Funding target amount
     * @param _milestones Array of milestone data (title, description, percentage, deadline)
     */
    function signValidate(
        uint256 _programId,
        address _projectOwner,
        string memory _projectName,
        uint256 _fundingTarget,
        MilestoneData[] memory _milestones
    ) external validProgram(_programId) onlyValidator(_programId) {
        InvestmentProgram storage program = investmentPrograms[_programId];

        // Check if we're in application period
        require(
            getProgramStatus(_programId) == ProgramStatus.ApplicationOngoing,
            "Not in application period"
        );
        require(_projectOwner != address(0), "Invalid project owner");
        require(bytes(_projectName).length > 0, "Project name cannot be empty");
        require(
            _fundingTarget > 0 &&
                _fundingTarget <= program.maxFundingPerProject,
            "Invalid funding target"
        );
        require(_milestones.length > 0, "At least one milestone required");

        // Validate milestone percentages sum to 100%
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _milestones.length; i++) {
            require(
                _milestones[i].percentage > 0,
                "Milestone percentage must be greater than 0"
            );
            require(
                _milestones[i].deadline > program.fundingEndTime,
                "Milestone deadline must be after funding ends"
            );
            totalPercentage += _milestones[i].percentage;
        }
        require(
            totalPercentage == 10000,
            "Milestone percentages must sum to 100%"
        );

        // Create validation request if it doesn't exist
        uint256 requestId = _findOrCreateValidationRequest(
            _projectOwner,
            _projectName,
            _fundingTarget
        );

        // Check if this validator has already approved this request
        ValidationRequest storage request = validationRequests[requestId];
        require(!request.processed, "Request already processed");

        // Create project if this is the first approval, or add approval
        uint256 projectId = _findProjectByOwnerAndProgram(
            _programId,
            _projectOwner
        );

        if (projectId == type(uint256).max) {
            // Create new project
            projectId = _createProject(
                _programId,
                _projectOwner,
                _projectName,
                _fundingTarget,
                _milestones
            );
        }

        Project storage project = projects[projectId];

        // Add validator approval
        if (!project.validatorApprovals[msg.sender]) {
            project.validatorApprovals[msg.sender] = true;
            project.approvalCount++;

            emit ProjectValidated(
                projectId,
                msg.sender,
                project.approvalCount,
                program.requiredApprovals
            );

            // Check if we have enough approvals
            if (project.approvalCount >= program.requiredApprovals) {
                request.processed = true;
                // Project is now approved and ready for funding
                emit ProjectCreated(
                    projectId,
                    _programId,
                    _projectOwner,
                    _projectName,
                    _fundingTarget
                );
            }
        }
    }

    /**
     * @dev Internal function to create a new project
     */
    function _createProject(
        uint256 _programId,
        address _projectOwner,
        string memory _projectName,
        uint256 _fundingTarget,
        MilestoneData[] memory _milestones
    ) internal returns (uint256) {
        uint256 projectId = nextProjectId++;
        InvestmentProgram storage program = investmentPrograms[_programId];

        Project storage project = projects[projectId];
        project.id = projectId;
        project.programId = _programId;
        project.owner = _projectOwner;
        project.name = _projectName;
        project.fundingTarget = _fundingTarget;
        project.totalFunded = 0;
        project.approvalCount = 0;
        project.status = ProjectStatus.Ready;
        project.milestoneCount = _milestones.length;
        project.totalPaidOut = 0;
        project.fundingSuccessful = false;
        project.createdAt = block.timestamp;

        // Add milestones
        for (uint256 i = 0; i < _milestones.length; i++) {
            project.milestones[i] = Milestone({
                id: i,
                title: _milestones[i].title,
                description: _milestones[i].description,
                percentage: _milestones[i].percentage,
                deadline: _milestones[i].deadline,
                completed: false,
                paid: false,
                amount: 0 // Will be calculated when funding is successful
            });
        }

        // Add project to program
        program.projectIds[program.projectCount] = projectId;
        program.projectCount++;

        return projectId;
    }

    /**
     * @dev Updates project details (only project owner can update before funding starts)
     */
    function updateProject(
        uint256 _projectId,
        string memory _projectName,
        uint256 _fundingTarget
    ) external validProject(_projectId) onlyProjectOwner(_projectId) {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        require(
            block.timestamp < program.fundingStartTime,
            "Cannot update after funding starts"
        );
        require(bytes(_projectName).length > 0, "Project name cannot be empty");
        require(
            _fundingTarget > 0 &&
                _fundingTarget <= program.maxFundingPerProject,
            "Invalid funding target"
        );

        project.name = _projectName;
        project.fundingTarget = _fundingTarget;

        emit ProjectUpdated(_projectId, _projectName, _fundingTarget);
    }

    // ===== INVESTMENT FUNCTIONS WITH PAUSE PROTECTION =====

    /**
     * @dev Supporters invest in a project
     * @param _projectId Project ID to invest in
     */
    function investFund(
        uint256 _projectId
    ) external payable validProject(_projectId) nonReentrant whenNotPaused {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        // Check timing and status
        require(
            getProgramStatus(project.programId) == ProgramStatus.FundingOngoing,
            "Not in funding period"
        );
        require(
            getProjectStatus(_projectId) == ProjectStatus.FundingOngoing,
            "Project not accepting funding"
        );
        require(
            project.approvalCount >= program.requiredApprovals,
            "Project not approved"
        );

        uint256 investmentAmount;

        // Handle ETH vs ERC20 investment
        if (program.token == ETH_ADDRESS) {
            require(msg.value > 0, "Investment amount must be greater than 0");
            investmentAmount = msg.value;
        } else {
            require(
                msg.value == 0,
                "Should not send ETH when investing with token"
            );
            // This function expects the frontend to handle token approval
            // The actual token transfer will be handled by external call
            revert("ERC20 investment should use investFundWithToken function");
        }

        // Check tier restrictions
        if (program.condition == InvestmentCondition.Tier) {
            TierInfo storage tierInfo = project.tierAssignments[msg.sender];
            require(tierInfo.isAssigned, "User not assigned to any tier");
            require(
                project.supporters[msg.sender] + investmentAmount <=
                    tierInfo.maxInvestment,
                "Investment exceeds tier limit"
            );
        }

        // Check funding target
        require(
            project.totalFunded + investmentAmount <= project.fundingTarget,
            "Investment exceeds funding target"
        );

        // Update project funding
        if (project.supporters[msg.sender] == 0) {
            project.supporterList.push(msg.sender);
        }
        project.supporters[msg.sender] += investmentAmount;
        project.totalFunded += investmentAmount;

        // Check if funding target is met
        if (project.totalFunded >= project.fundingTarget) {
            project.fundingSuccessful = true;
            _calculateMilestoneAmounts(_projectId);
        }

        emit InvestmentMade(
            _projectId,
            msg.sender,
            investmentAmount,
            project.totalFunded
        );
    }

    /**
     * @dev Supporters invest in a project using ERC20 tokens
     * @param _projectId Project ID to invest in
     * @param _amount Amount to invest
     */
    function investFundWithToken(
        uint256 _projectId,
        uint256 _amount
    ) external validProject(_projectId) nonReentrant whenNotPaused {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        require(
            program.token != ETH_ADDRESS,
            "Use investFund for ETH investments"
        );
        require(_amount > 0, "Investment amount must be greater than 0");

        // Check timing and status
        require(
            getProgramStatus(project.programId) == ProgramStatus.FundingOngoing,
            "Not in funding period"
        );
        require(
            getProjectStatus(_projectId) == ProjectStatus.FundingOngoing,
            "Project not accepting funding"
        );
        require(
            project.approvalCount >= program.requiredApprovals,
            "Project not approved"
        );

        // Check tier restrictions
        if (program.condition == InvestmentCondition.Tier) {
            TierInfo storage tierInfo = project.tierAssignments[msg.sender];
            require(tierInfo.isAssigned, "User not assigned to any tier");
            require(
                project.supporters[msg.sender] + _amount <=
                    tierInfo.maxInvestment,
                "Investment exceeds tier limit"
            );
        }

        // Check funding target
        require(
            project.totalFunded + _amount <= project.fundingTarget,
            "Investment exceeds funding target"
        );

        // Transfer tokens from investor
        IERC20(program.token).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Update project funding
        if (project.supporters[msg.sender] == 0) {
            project.supporterList.push(msg.sender);
        }
        project.supporters[msg.sender] += _amount;
        project.totalFunded += _amount;

        // Check if funding target is met
        if (project.totalFunded >= project.fundingTarget) {
            project.fundingSuccessful = true;
            _calculateMilestoneAmounts(_projectId);
        }

        emit InvestmentMade(
            _projectId,
            msg.sender,
            _amount,
            project.totalFunded
        );
    }

    /**
     * @dev Supporters reclaim their funds if project failed or milestone deadline missed
     * @param _projectId Project ID to reclaim from
     */
    function reclaimFund(
        uint256 _projectId
    ) external validProject(_projectId) nonReentrant whenNotPaused {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        uint256 supporterInvestment = project.supporters[msg.sender];
        require(supporterInvestment > 0, "No investment to reclaim");

        // Check if reclaim is allowed
        bool canReclaim = false;

        // Case 1: Funding target not met after funding period
        if (
            block.timestamp > program.fundingEndTime &&
            !project.fundingSuccessful
        ) {
            canReclaim = true;
        }

        // Case 2: Milestone deadline missed (use cached check for gas optimization)
        if (project.fundingSuccessful) {
            if (block.timestamp > project.lastMilestoneCheck + 1 hours) {
                // Only check milestones once per hour to save gas
                _checkMilestoneDeadlines(_projectId);
            }

            if (project.hasFailedMilestone) {
                canReclaim = true;
            }
        }

        require(canReclaim, "Cannot reclaim funds at this time");

        // Calculate reclaim amount (total investment minus already paid out proportionally)
        uint256 reclaimAmount = supporterInvestment;
        if (project.totalPaidOut > 0) {
            uint256 paidPercentage = (project.totalPaidOut * 10000) /
                project.totalFunded;
            uint256 deduction = (supporterInvestment * paidPercentage) / 10000;
            reclaimAmount = supporterInvestment - deduction;
        }

        require(reclaimAmount > 0, "No funds available to reclaim");

        // Update supporter investment
        project.supporters[msg.sender] = 0;

        // Transfer funds back to supporter
        if (program.token == ETH_ADDRESS) {
            (bool sent, ) = payable(msg.sender).call{value: reclaimAmount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(program.token).safeTransfer(msg.sender, reclaimAmount);
        }

        emit FundsReclaimed(_projectId, msg.sender, reclaimAmount);
    }

    /**
     * @dev Host claims fee after funding ends and enters pending state
     * @param _programId Program ID
     */
    function feeClaim(
        uint256 _programId
    )
        external
        validProgram(_programId)
        onlyProgramHost(_programId)
        nonReentrant
        whenNotPaused
    {
        InvestmentProgram storage program = investmentPrograms[_programId];

        require(
            block.timestamp > program.fundingEndTime,
            "Funding period not ended"
        );
        require(!program.feeClaimed, "Fee already claimed");

        // Calculate total successful funding across all projects
        uint256 totalSuccessfulFunding = 0;
        for (uint256 i = 0; i < program.projectCount; i++) {
            uint256 projectId = program.projectIds[i];
            Project storage project = projects[projectId];
            if (project.fundingSuccessful) {
                totalSuccessfulFunding += project.totalFunded;
            }
        }

        require(
            totalSuccessfulFunding > 0,
            "No successful funding to claim fee from"
        );

        // Calculate fee amount
        uint256 feeAmount = (totalSuccessfulFunding * program.feePercentage) /
            10000;

        program.feeClaimed = true;
        program.totalFeeCollected = feeAmount;

        // Transfer fee to host
        if (program.token == ETH_ADDRESS) {
            (bool sent, ) = payable(program.host).call{value: feeAmount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(program.token).safeTransfer(program.host, feeAmount);
        }

        emit FeeClaimed(_programId, program.host, feeAmount);
    }

    // ===== MILESTONE FUNCTIONS WITH PAUSE PROTECTION =====

    /**
     * @dev Validator accepts a milestone and pays out to project owner
     * @param _projectId Project ID
     * @param _milestoneId Milestone ID
     */
    function acceptMilestone(
        uint256 _projectId,
        uint256 _milestoneId
    ) external validProject(_projectId) nonReentrant whenNotPaused {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        // Check validator permissions using gas-optimized lookup
        require(program.validatorMapping[msg.sender], "Not a validator");
        require(
            _milestoneId < project.milestoneCount,
            "Milestone does not exist"
        );
        require(
            project.fundingSuccessful,
            "Project funding was not successful"
        );
        require(
            block.timestamp > program.fundingEndTime,
            "Funding period not ended"
        );

        Milestone storage milestone = project.milestones[_milestoneId];
        require(!milestone.completed, "Milestone already completed");
        require(!milestone.paid, "Milestone already paid");
        require(
            block.timestamp <= milestone.deadline,
            "Milestone deadline passed"
        );

        // Mark milestone as completed and paid
        milestone.completed = true;
        milestone.paid = true;

        uint256 payoutAmount = milestone.amount;
        project.totalPaidOut += payoutAmount;

        // Transfer payment to project owner
        if (program.token == ETH_ADDRESS) {
            (bool sent, ) = payable(project.owner).call{value: payoutAmount}(
                ""
            );
            require(sent, "ETH transfer failed");
        } else {
            IERC20(program.token).safeTransfer(project.owner, payoutAmount);
        }

        // Gas optimized: Check completion without loop
        _checkAllMilestonesCompleted(_projectId);

        emit MilestoneAccepted(
            _projectId,
            _milestoneId,
            project.owner,
            payoutAmount
        );
    }

    /**
     * @dev Public function to check and mark expired milestones
     * @param _projectId Project ID
     */
    function checkMilestoneDeadline(
        uint256 _projectId
    ) external validProject(_projectId) whenNotPaused {
        _checkMilestoneDeadlines(_projectId);
    }

    // ===== HELPER FUNCTIONS =====

    /**
     * @dev Calculate milestone amounts based on funding success
     */
    function _calculateMilestoneAmounts(uint256 _projectId) internal {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[
            project.programId
        ];

        // Calculate amounts minus fee
        uint256 totalAmount = project.totalFunded;
        uint256 feeAmount = (totalAmount * program.feePercentage) / 10000;
        uint256 availableForMilestones = totalAmount - feeAmount;

        for (uint256 i = 0; i < project.milestoneCount; i++) {
            Milestone storage milestone = project.milestones[i];
            milestone.amount =
                (availableForMilestones * milestone.percentage) /
                10000;
        }
    }

    /**
     * @dev Find or create validation request
     */
    function _findOrCreateValidationRequest(
        address _projectOwner,
        string memory _projectName,
        uint256 _fundingTarget
    ) internal returns (uint256) {
        // For simplicity, create a new request each time
        // In production, you might want to check for existing requests
        uint256 requestId = nextValidationRequestId++;

        validationRequests[requestId] = ValidationRequest({
            projectId: 0, // Will be set when project is created
            projectOwner: _projectOwner,
            projectName: _projectName,
            fundingTarget: _fundingTarget,
            timestamp: block.timestamp,
            processed: false
        });

        return requestId;
    }

    /**
     * @dev Find project by owner and program
     */
    function _findProjectByOwnerAndProgram(
        uint256 _programId,
        address _owner
    ) internal view returns (uint256) {
        InvestmentProgram storage program = investmentPrograms[_programId];

        for (uint256 i = 0; i < program.projectCount; i++) {
            uint256 projectId = program.projectIds[i];
            if (projects[projectId].owner == _owner) {
                return projectId;
            }
        }

        return type(uint256).max; // Not found
    }

    /**
     * @dev Check if address is a validator for a program
     */
    function _isValidator(
        uint256 _programId,
        address _validator
    ) internal view returns (bool) {
        return investmentPrograms[_programId].validatorMapping[_validator];
    }

    // ===== GAS-OPTIMIZED HELPER FUNCTIONS =====

    /**
     * @dev Internal function to check milestone deadlines with caching
     */
    function _checkMilestoneDeadlines(uint256 _projectId) internal {
        Project storage project = projects[_projectId];

        require(
            project.fundingSuccessful,
            "Project funding was not successful"
        );

        bool hasExpiredMilestones = false;
        for (uint256 i = 0; i < project.milestoneCount; i++) {
            Milestone storage milestone = project.milestones[i];
            if (!milestone.completed && block.timestamp > milestone.deadline) {
                hasExpiredMilestones = true;
                break;
            }
        }

        // Update cache
        project.hasFailedMilestone = hasExpiredMilestones;
        project.lastMilestoneCheck = block.timestamp;

        if (
            hasExpiredMilestones &&
            project.status != ProjectStatus.ProjectFailed
        ) {
            ProjectStatus oldStatus = project.status;
            project.status = ProjectStatus.ProjectFailed;
            emit ProjectStatusChanged(
                _projectId,
                oldStatus,
                ProjectStatus.ProjectFailed
            );
        }
    }

    /**
     * @dev Internal function to efficiently check if all milestones are completed
     */
    function _checkAllMilestonesCompleted(uint256 _projectId) internal {
        Project storage project = projects[_projectId];

        // Early exit if no milestones or already completed
        if (
            project.milestoneCount == 0 ||
            project.status == ProjectStatus.ProjectCompleted
        ) {
            return;
        }

        // Check if all milestones are completed
        bool allCompleted = true;
        for (uint256 i = 0; i < project.milestoneCount; i++) {
            if (!project.milestones[i].completed) {
                allCompleted = false;
                break;
            }
        }

        if (allCompleted) {
            ProjectStatus oldStatus = project.status;
            project.status = ProjectStatus.ProjectCompleted;
            emit ProjectStatusChanged(
                _projectId,
                oldStatus,
                ProjectStatus.ProjectCompleted
            );
        }
    }

    // ===== BATCH OPERATIONS FOR BETTER GAS EFFICIENCY =====

    /**
     * @dev Batch function to check multiple project statuses at once
     * @param _projectIds Array of project IDs to check
     * @return Array of project statuses
     */
    function batchGetProjectStatus(
        uint256[] calldata _projectIds
    ) external view returns (ProjectStatus[] memory) {
        ProjectStatus[] memory statuses = new ProjectStatus[](
            _projectIds.length
        );
        for (uint256 i = 0; i < _projectIds.length; i++) {
            statuses[i] = getProjectStatus(_projectIds[i]);
        }
        return statuses;
    }

    /**
     * @dev Batch function to check multiple program statuses at once
     * @param _programIds Array of program IDs to check
     * @return Array of program statuses
     */
    function batchGetProgramStatus(
        uint256[] calldata _programIds
    ) external view returns (ProgramStatus[] memory) {
        ProgramStatus[] memory statuses = new ProgramStatus[](
            _programIds.length
        );
        for (uint256 i = 0; i < _programIds.length; i++) {
            statuses[i] = getProgramStatus(_programIds[i]);
        }
        return statuses;
    }

    /**
     * @dev Batch function to get user investments in multiple projects
     * @param _projectIds Array of project IDs
     * @param _user User address
     * @return Array of investment amounts
     */
    function batchGetUserInvestments(
        uint256[] calldata _projectIds,
        address _user
    ) external view returns (uint256[] memory) {
        uint256[] memory investments = new uint256[](_projectIds.length);
        for (uint256 i = 0; i < _projectIds.length; i++) {
            investments[i] = projects[_projectIds[i]].supporters[_user];
        }
        return investments;
    }

    /**
     * @dev Get paginated project list for a program to avoid gas limit issues
     * @param _programId Program ID
     * @param _offset Starting index
     * @param _limit Maximum number of items to return
     * @return Array of project IDs and total count
     */
    function getPaginatedProgramProjects(
        uint256 _programId,
        uint256 _offset,
        uint256 _limit
    )
        external
        view
        validProgram(_programId)
        returns (uint256[] memory, uint256)
    {
        InvestmentProgram storage program = investmentPrograms[_programId];
        uint256 totalCount = program.projectCount;

        if (_offset >= totalCount) {
            return (new uint256[](0), totalCount);
        }

        uint256 end = _offset + _limit;
        if (end > totalCount) {
            end = totalCount;
        }

        uint256[] memory projectIds = new uint256[](end - _offset);
        for (uint256 i = _offset; i < end; i++) {
            projectIds[i - _offset] = program.projectIds[i];
        }

        return (projectIds, totalCount);
    }

    // ===== MONITORING AND MAINTENANCE FUNCTIONS =====

    /**
     * @dev Function to update status cache for a program (can be called by anyone)
     * @param _programId Program ID
     */
    function updateProgramStatusCache(
        uint256 _programId
    ) external validProgram(_programId) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        program.status = getProgramStatus(_programId);
        program.lastStatusUpdate = block.timestamp;
        program.statusCacheValid = true;
    }

    /**
     * @dev Function to batch update milestone deadline checks (can be called by anyone)
     * @param _projectIds Array of project IDs to check
     */
    function batchCheckMilestoneDeadlines(
        uint256[] calldata _projectIds
    ) external {
        for (uint256 i = 0; i < _projectIds.length; i++) {
            if (_projectIds[i] < nextProjectId) {
                _checkMilestoneDeadlines(_projectIds[i]);
            }
        }
    }

    // ===== ANALYTICS AND REPORTING FUNCTIONS =====

    /**
     * @dev Get program statistics for analytics
     * @param _programId Program ID
     * @return totalProjects Total number of projects in the program
     * @return successfulProjects Number of projects that met funding target
     * @return totalFunding Total amount of funding across all successful projects
     * @return totalFees Total fees collected by the program
     */
    function getProgramAnalytics(
        uint256 _programId
    )
        external
        view
        validProgram(_programId)
        returns (
            uint256 totalProjects,
            uint256 successfulProjects,
            uint256 totalFunding,
            uint256 totalFees
        )
    {
        InvestmentProgram storage program = investmentPrograms[_programId];
        totalProjects = program.projectCount;
        totalFees = program.totalFeeCollected;

        for (uint256 i = 0; i < program.projectCount; i++) {
            uint256 projectId = program.projectIds[i];
            Project storage project = projects[projectId];

            if (project.fundingSuccessful) {
                successfulProjects++;
                totalFunding += project.totalFunded;
            }
        }
    }

    /**
     * @dev Get project funding progress
     * @param _projectId Project ID
     * @return currentFunding Current amount of funding raised
     * @return targetFunding Target funding amount for the project
     * @return percentageFunded Percentage of target reached (in basis points)
     * @return supporterCount Number of unique supporters
     */
    function getProjectFundingProgress(
        uint256 _projectId
    )
        external
        view
        validProject(_projectId)
        returns (
            uint256 currentFunding,
            uint256 targetFunding,
            uint256 percentageFunded,
            uint256 supporterCount
        )
    {
        Project storage project = projects[_projectId];
        currentFunding = project.totalFunded;
        targetFunding = project.fundingTarget;
        percentageFunded = targetFunding > 0
            ? (currentFunding * 10000) / targetFunding
            : 0;
        supporterCount = project.supporterList.length;
    }

    // ===== EMERGENCY FUNCTIONS =====

    /**
     * @dev Emergency function to force-update a project status (only owner)
     * @param _projectId Project ID
     * @param _newStatus New project status
     */
    function emergencyUpdateProjectStatus(
        uint256 _projectId,
        ProjectStatus _newStatus
    ) external onlyOwner validProject(_projectId) {
        Project storage project = projects[_projectId];
        ProjectStatus oldStatus = project.status;
        project.status = _newStatus;

        emit ProjectStatusChanged(_projectId, oldStatus, _newStatus);
    }

    /**
     * @dev Emergency function to force-update a program status (only owner)
     * @param _programId Program ID
     * @param _newStatus New program status
     */
    function emergencyUpdateProgramStatus(
        uint256 _programId,
        ProgramStatus _newStatus
    ) external onlyOwner validProgram(_programId) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        ProgramStatus oldStatus = program.status;
        program.status = _newStatus;
        program.statusCacheValid = false;

        emit ProgramStatusChanged(_programId, oldStatus, _newStatus);
    }
}
