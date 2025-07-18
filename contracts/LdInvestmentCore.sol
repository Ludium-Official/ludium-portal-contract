// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILdInvestmentCore.sol";
import "./interfaces/ILdTimeLock.sol";
import "./interfaces/ILdMilestoneManager.sol";
import "./interfaces/ILdFunding.sol";
import "./libraries/Errors.sol";

/**
 * @title LdInvestmentCore
 * @dev Main contract for Ludium Investment Program with modular architecture
 * This contract orchestrates the other modules and manages core state
 */
contract LdInvestmentCore is ILdInvestmentCore, Ownable, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Constants
    address public constant ETH_ADDRESS = address(0);
    uint256 public constant PENDING_PERIOD = 24 * 60 * 60; // 1 day
    uint256 public constant MAX_VALIDATORS_PER_PROGRAM = 10;
    uint256 public constant MAX_PROJECTS_PER_BATCH = 20;
    
    // Fee and percentage constants
    uint16 public constant DEFAULT_FEE_PERCENTAGE = 300; // 3%
    uint16 public constant MAX_FEE_PERCENTAGE = 1000; // 10%
    uint16 public constant PERCENTAGE_BASIS_POINTS = 10000; // 100%
    
    // Cache and timing constants
    uint256 public constant STATUS_CACHE_DURATION = 1 hours;
    uint256 public constant MIN_INVESTMENT_AMOUNT = 1; // Minimum 1 wei
    uint256 public constant MIN_FUNDING_AMOUNT = 1; // Minimum 1 wei for funding target
    
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROGRAM_MANAGER_ROLE = keccak256("PROGRAM_MANAGER_ROLE");
    bytes32 public constant VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    // State variables
    mapping(uint256 => InvestmentProgram) public investmentPrograms;
    mapping(uint256 => Project) public projects;
    mapping(address => bool) public whitelistedTokens;
    
    uint256 public nextProgramId;
    uint256 public nextProjectId;
    uint16 public defaultFeePercentage = DEFAULT_FEE_PERCENTAGE;
    
    // Module contracts
    ILdTimeLock public timeLockModule;
    ILdMilestoneManager public milestoneModule;
    ILdFunding public fundingModule;
    
    // Modifiers
    modifier validProgram(uint256 _programId) {
        if (_programId >= nextProgramId) {
            revert Errors.InvalidProgramId(_programId);
        }
        _;
    }
    
    modifier validProject(uint256 _projectId) {
        if (_projectId >= nextProjectId) {
            revert Errors.InvalidProjectId(_projectId);
        }
        _;
    }
    
    modifier withinGasLimits(uint256 _validatorCount, uint256 _projectCount) {
        if (_validatorCount > MAX_VALIDATORS_PER_PROGRAM) {
            revert Errors.TooManyValidators(_validatorCount, MAX_VALIDATORS_PER_PROGRAM);
        }
        if (_projectCount > MAX_PROJECTS_PER_BATCH) {
            revert Errors.TooManyProjects(_projectCount, MAX_PROJECTS_PER_BATCH);
        }
        _;
    }
    
    modifier onlyProgramManager() {
        if (!hasRole(PROGRAM_MANAGER_ROLE, msg.sender)) {
            revert Errors.NotProgramManager(msg.sender);
        }
        _;
    }
    
    modifier onlyTokenManager() {
        if (!hasRole(TOKEN_MANAGER_ROLE, msg.sender)) {
            revert Errors.NotTokenManager(msg.sender);
        }
        _;
    }
    
    modifier onlyPauserRole() {
        if (!hasRole(PAUSER_ROLE, msg.sender)) {
            revert Errors.NotPauserRole(msg.sender);
        }
        _;
    }
    
    modifier onlyOwnerOrAdmin() {
        if (msg.sender != owner() && !hasRole(ADMIN_ROLE, msg.sender)) {
            revert Errors.NotOwnerOrAdmin(msg.sender);
        }
        _;
    }
    
    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
        
        // Set up role hierarchy
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ADMIN_ROLE, initialOwner);
        _grantRole(PROGRAM_MANAGER_ROLE, initialOwner);
        _grantRole(VALIDATOR_MANAGER_ROLE, initialOwner);
        _grantRole(TOKEN_MANAGER_ROLE, initialOwner);
        _grantRole(EMERGENCY_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, initialOwner);
        
        // Set role admins
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PROGRAM_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(VALIDATOR_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TOKEN_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
        
        whitelistedTokens[ETH_ADDRESS] = true;
    }
    
    /**
     * @dev Set module contracts
     */
    function setModules(
        address _timeLockModule,
        address _milestoneModule,
        address _fundingModule
    ) external onlyOwner {
        timeLockModule = ILdTimeLock(_timeLockModule);
        milestoneModule = ILdMilestoneManager(_milestoneModule);
        fundingModule = ILdFunding(_fundingModule);
    }
    
    /**
     * @dev Creates a new investment program
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
        if (bytes(_name).length == 0) {
            revert Errors.EmptyProgramName();
        }
        if (_validators.length == 0) {
            revert Errors.InvalidApprovalCount(1, 0);
        }
        if (_requiredApprovals == 0 || _requiredApprovals > _validators.length) {
            revert Errors.InvalidApprovalCount(_requiredApprovals, _validators.length);
        }
        require(_requiredApprovals <= type(uint16).max, "Too many required approvals");
        require(_maxFundingPerProject >= MIN_FUNDING_AMOUNT, "Max funding must be greater than 0");
        if (_applicationStartTime <= block.timestamp) {
            revert Errors.InvalidApplicationTime(_applicationStartTime);
        }
        require(_applicationEndTime > _applicationStartTime, "Invalid application time range");
        require(_fundingStartTime >= _applicationEndTime, "Funding start must be after application end");
        require(_fundingEndTime > _fundingStartTime, "Invalid funding time range");
        if (_feePercentage > MAX_FEE_PERCENTAGE) {
            revert Errors.FeePercentageTooHigh(_feePercentage, MAX_FEE_PERCENTAGE);
        }
        if (_feePercentage > type(uint16).max) {
            revert Errors.FeePercentageExceedsLimit(_feePercentage);
        }
        if (!whitelistedTokens[_token]) {
            revert Errors.TokenNotWhitelisted(_token);
        }

        uint256 programId = nextProgramId++;

        InvestmentProgram storage program = investmentPrograms[programId];
        program.id = programId;
        program.name = _name;
        program.host = msg.sender;
        program.requiredApprovals = uint16(_requiredApprovals);
        program.maxFundingPerProject = _maxFundingPerProject;
        program.applicationStartTime = _applicationStartTime;
        program.applicationEndTime = _applicationEndTime;
        program.fundingStartTime = _fundingStartTime;
        program.fundingEndTime = _fundingEndTime;
        program.condition = _condition;
        program.feePercentage = uint16(_feePercentage > 0 ? _feePercentage : defaultFeePercentage);
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
     * @dev Validate a project (only validators can call this)
     */
    function signValidate(
        uint256 _programId,
        address _projectOwner,
        string memory _projectName,
        uint256 _targetFunding,
        MilestoneInput[] memory _milestones
    ) external validProgram(_programId) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        require(program.validatorMapping[msg.sender], "Not a validator for this program");
        require(block.timestamp >= program.applicationStartTime, "Application period not started");
        require(block.timestamp <= program.applicationEndTime, "Application period ended");
        require(_targetFunding <= program.maxFundingPerProject, "Target funding exceeds program limit");
        require(bytes(_projectName).length > 0, "Project name cannot be empty");
        require(_milestones.length > 0, "At least one milestone required");
        
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _milestones.length; i++) {
            require(bytes(_milestones[i].title).length > 0, "Milestone title cannot be empty");
            require(_milestones[i].percentage > 0, "Milestone percentage must be greater than 0");
            require(_milestones[i].percentage <= type(uint16).max, "Milestone percentage exceeds uint16 limit");
            require(_milestones[i].deadline > program.fundingEndTime, "Milestone deadline must be after funding ends");
            totalPercentage += _milestones[i].percentage;
        }
        require(totalPercentage == PERCENTAGE_BASIS_POINTS, "Total milestone percentage must equal 100%");

        uint256 projectId = nextProjectId++;
        
        Project storage project = projects[projectId];
        project.id = projectId;
        project.programId = _programId;
        project.name = _projectName;
        project.owner = _projectOwner;
        project.targetFunding = _targetFunding;
        project.totalInvested = 0;
        project.status = ProjectStatus.Pending;
        project.supporterCount = 0;
        project.fundsReclaimed = false;
        project.termsCount = 0;
        
        program.projectCount++;
        
        // Create milestones through milestone module (would need to implement)
        // For now, this is a placeholder - actual milestone creation would go to milestone module
        
        emit ProjectValidated(_programId, projectId, _projectOwner, _projectName, _targetFunding);
    }
    
    /**
     * @dev Get program details
     */
    function getProgramDetails(uint256 _programId) external view validProgram(_programId) returns (
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
    ) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        return (
            program.name,
            program.host,
            program.maxFundingPerProject,
            program.applicationStartTime,
            program.applicationEndTime,
            program.fundingStartTime,
            program.fundingEndTime,
            program.condition,
            program.feePercentage,
            program.status,
            program.token,
            program.feeClaimed
        );
    }
    
    /**
     * @dev Get project details
     */
    function getProjectDetails(uint256 _projectId) external view validProject(_projectId) returns (
        string memory name,
        address owner,
        uint256 targetFunding,
        uint256 totalInvested,
        ProjectStatus status,
        uint256 programId
    ) {
        Project storage project = projects[_projectId];
        return (
            project.name,
            project.owner,
            project.targetFunding,
            project.totalInvested,
            project.status,
            project.programId
        );
    }
    
    /**
     * @dev Get program status based on current time and conditions
     */
    function getProgramStatus(uint256 programId) public view validProgram(programId) returns (ProgramStatus) {
        InvestmentProgram storage program = investmentPrograms[programId];

        // Use cached status if valid and not too old (1 hour)
        if (program.statusCacheValid && block.timestamp < program.lastStatusUpdate + STATUS_CACHE_DURATION) {
            return program.status;
        }

        // Manual status override takes priority
        if (program.status == ProgramStatus.Failed || program.status == ProgramStatus.Successful) {
            return program.status;
        }

        uint256 currentTime = block.timestamp;
        
        if (currentTime < program.applicationStartTime) {
            return ProgramStatus.Ready;
        } else if (currentTime < program.fundingEndTime) {
            return ProgramStatus.Active;
        } else if (currentTime < program.fundingEndTime + PENDING_PERIOD) {
            return ProgramStatus.Pending;
        } else {
            // Check if program was successful based on projects
            // This would need more complex logic to check actual project success
            return ProgramStatus.Successful;
        }
    }
    
    // Token whitelist management
    function setTokenWhitelist(address token, bool status) external onlyTokenManager {
        whitelistedTokens[token] = status;
        emit TokenWhitelisted(token, status);
    }
    
    // Set default fee percentage
    function setDefaultFeePercentage(uint256 _feePercentage) external onlyOwnerOrAdmin {
        require(_feePercentage <= MAX_FEE_PERCENTAGE, "Fee percentage too high"); // Max 10%
        require(_feePercentage <= type(uint16).max, "Fee percentage exceeds uint16 limit");
        defaultFeePercentage = uint16(_feePercentage);
    }
    
    // Pause functions
    function pause() external onlyPauserRole {
        _pause();
    }

    function unpause() external onlyPauserRole {
        _unpause();
    }
    
    // Role management functions
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        super.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == msg.sender, "AccessControl: can only renounce roles for self");
        super.renounceRole(role, account);
    }
    
    // Get validator count
    function getValidatorCount(uint256 _programId) external view validProgram(_programId) returns (uint256) {
        return investmentPrograms[_programId].validators.length;
    }
    
    // Get validator at index
    function getValidatorAt(uint256 _programId, uint256 _index) external view validProgram(_programId) returns (address) {
        require(_index < investmentPrograms[_programId].validators.length, "Index out of bounds");
        return investmentPrograms[_programId].validators[_index];
    }
    
    // ===== AUTOMATIC STATUS TRANSITION FUNCTIONS =====
    
    /**
     * @dev Update program status based on current time and conditions
     * @param _programId Program ID to update
     * @return newStatus The new status after update
     */
    function updateProgramStatus(uint256 _programId) external validProgram(_programId) returns (ProgramStatus) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        ProgramStatus oldStatus = program.status;
        ProgramStatus newStatus = _calculateProgramStatus(_programId);
        
        if (oldStatus != newStatus) {
            program.status = newStatus;
            program.lastStatusUpdate = block.timestamp;
            program.statusCacheValid = true;
            
            emit ProgramStatusChanged(_programId, oldStatus, newStatus);
        }
        
        return newStatus;
    }
    
    /**
     * @dev Update project status based on milestone deadlines and funding
     * @param _projectId Project ID to update
     * @return newStatus The new status after update
     */
    function updateProjectStatus(uint256 _projectId) external validProject(_projectId) returns (ProjectStatus) {
        Project storage project = projects[_projectId];
        ProjectStatus oldStatus = project.status;
        ProjectStatus newStatus = _calculateProjectStatus(_projectId);
        
        if (oldStatus != newStatus) {
            project.status = newStatus;
            emit ProjectStatusChanged(_projectId, oldStatus, newStatus);
        }
        
        return newStatus;
    }
    
    /**
     * @dev Batch update multiple program statuses
     * @param _programIds Array of program IDs to update
     */
    function batchUpdateProgramStatuses(uint256[] calldata _programIds) external {
        require(_programIds.length <= MAX_PROJECTS_PER_BATCH, "Too many programs in batch");
        
        for (uint256 i = 0; i < _programIds.length; i++) {
            if (_programIds[i] < nextProgramId) {
                this.updateProgramStatus(_programIds[i]);
            }
        }
    }
    
    /**
     * @dev Batch update multiple project statuses
     * @param _projectIds Array of project IDs to update  
     */
    function batchUpdateProjectStatuses(uint256[] calldata _projectIds) external {
        require(_projectIds.length <= MAX_PROJECTS_PER_BATCH, "Too many projects in batch");
        
        for (uint256 i = 0; i < _projectIds.length; i++) {
            if (_projectIds[i] < nextProjectId) {
                this.updateProjectStatus(_projectIds[i]);
            }
        }
    }
    
    /**
     * @dev Internal function to calculate program status based on timing and conditions
     * @param _programId Program ID
     * @return calculated status
     */
    function _calculateProgramStatus(uint256 _programId) internal view returns (ProgramStatus) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        
        // Manual status override takes priority (Failed/Successful are final)
        if (program.status == ProgramStatus.Failed || program.status == ProgramStatus.Successful) {
            return program.status;
        }
        
        uint256 currentTime = block.timestamp;
        
        // Time-based transitions
        if (currentTime < program.applicationStartTime) {
            return ProgramStatus.Ready;
        } else if (currentTime < program.fundingEndTime) {
            return ProgramStatus.Active;
        } else if (currentTime < program.fundingEndTime + PENDING_PERIOD) {
            return ProgramStatus.Pending;
        } else {
            // After pending period, determine success based on project outcomes
            return _evaluateProgramSuccess(_programId);
        }
    }
    
    /**
     * @dev Internal function to calculate project status based on milestone deadlines
     * @param _projectId Project ID
     * @return calculated status
     */
    function _calculateProjectStatus(uint256 _projectId) internal view returns (ProjectStatus) {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[project.programId];
        
        // Manual status override takes priority (final statuses)
        if (project.status == ProjectStatus.Successful || 
            project.status == ProjectStatus.Failed || 
            project.status == ProjectStatus.Cancelled) {
            return project.status;
        }
        
        uint256 currentTime = block.timestamp;
        
        // If funding period hasn't ended, check if project should be active
        if (currentTime < program.fundingEndTime) {
            if (project.totalInvested > 0) {
                return ProjectStatus.Active;
            } else {
                return ProjectStatus.Pending;
            }
        }
        
        // After funding period, check milestone deadlines
        if (currentTime > program.fundingEndTime) {
            // If no funding received, mark as failed
            if (project.totalInvested == 0) {
                return ProjectStatus.Failed;
            }
            
            // Check if any milestone deadlines have passed
            // Note: This would require milestone module integration
            // For now, return Active if funded
            return ProjectStatus.Active;
        }
        
        return project.status;
    }
    
    /**
     * @dev Evaluate if a program should be marked as successful based on project outcomes
     * @param _programId Program ID
     * @return ProgramStatus.Successful or ProgramStatus.Failed
     */
    function _evaluateProgramSuccess(uint256 _programId) internal view returns (ProgramStatus) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        
        // Simple logic: if at least one project received funding, consider successful
        // More complex logic would check actual project completion rates
        // Note: This would require iterating through projects, which is gas-intensive
        // In practice, this should be tracked as a program state variable
        
        // For now, if the program has projects, assume some level of success
        if (program.projectCount > 0) {
            return ProgramStatus.Successful;
        } else {
            return ProgramStatus.Failed;
        }
    }
    
    /**
     * @dev Get programs that need status updates
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of programs to return
     * @return programIds Array of program IDs needing updates
     * @return hasMore Whether there are more programs to check
     */
    function getProgramsNeedingStatusUpdate(uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory programIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;
        uint256 checked = 0;
        
        for (uint256 i = _offset; i < nextProgramId && count < _limit; i++) {
            InvestmentProgram storage program = investmentPrograms[i];
            
            // Check if status might need updating (cache expired or time-based transition possible)
            if (!program.statusCacheValid || 
                block.timestamp >= program.lastStatusUpdate + STATUS_CACHE_DURATION ||
                _statusTransitionPossible(i)) {
                candidates[count] = i;
                count++;
            }
            checked++;
        }
        
        // Resize array to actual count
        programIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            programIds[i] = candidates[i];
        }
        
        hasMore = (_offset + checked) < nextProgramId;
        return (programIds, hasMore);
    }
    
    /**
     * @dev Check if a program status transition is possible based on timing
     * @param _programId Program ID to check
     * @return true if transition is possible
     */
    function _statusTransitionPossible(uint256 _programId) internal view returns (bool) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        uint256 currentTime = block.timestamp;
        
        // Check critical time boundaries where transitions occur
        return (currentTime >= program.applicationStartTime && program.status == ProgramStatus.Ready) ||
               (currentTime >= program.fundingEndTime && program.status == ProgramStatus.Active) ||
               (currentTime >= program.fundingEndTime + PENDING_PERIOD && program.status == ProgramStatus.Pending);
    }
    
    /**
     * @dev Force status cache refresh for a program
     * @param _programId Program ID
     */
    function refreshProgramStatusCache(uint256 _programId) external validProgram(_programId) {
        InvestmentProgram storage program = investmentPrograms[_programId];
        program.statusCacheValid = false;
        program.lastStatusUpdate = 0;
    }
    
    // ===== PAGINATION FUNCTIONS FOR GAS OPTIMIZATION =====
    
    /**
     * @dev Get paginated list of all programs
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of programs to return
     * @return programIds Array of program IDs
     * @return hasMore Whether there are more programs
     */
    function getAllPrograms(uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory programIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        
        // Handle empty case
        if (nextProgramId == 0) {
            return (new uint256[](0), false);
        }
        
        require(_offset < nextProgramId, "Offset out of bounds");
        
        uint256 end = _offset + _limit;
        if (end > nextProgramId) {
            end = nextProgramId;
        }
        
        uint256 length = end - _offset;
        programIds = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            programIds[i] = _offset + i;
        }
        
        hasMore = end < nextProgramId;
        return (programIds, hasMore);
    }
    
    /**
     * @dev Get paginated list of all projects
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of projects to return
     * @return projectIds Array of project IDs
     * @return hasMore Whether there are more projects
     */
    function getAllProjects(uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory projectIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        
        // Handle empty case
        if (nextProjectId == 0) {
            return (new uint256[](0), false);
        }
        
        require(_offset < nextProjectId, "Offset out of bounds");
        
        uint256 end = _offset + _limit;
        if (end > nextProjectId) {
            end = nextProjectId;
        }
        
        uint256 length = end - _offset;
        projectIds = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            projectIds[i] = _offset + i;
        }
        
        hasMore = end < nextProjectId;
        return (projectIds, hasMore);
    }
    
    /**
     * @dev Get paginated list of projects for a specific program
     * @param _programId Program ID to get projects for
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of projects to return
     * @return projectIds Array of project IDs in the program
     * @return hasMore Whether there are more projects
     */
    function getProjectsByProgram(uint256 _programId, uint256 _offset, uint256 _limit) 
        external 
        view 
        validProgram(_programId)
        returns (uint256[] memory projectIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;
        uint256 checked = 0;
        
        // Iterate through all projects to find ones belonging to this program
        for (uint256 i = _offset; i < nextProjectId && count < _limit; i++) {
            if (projects[i].programId == _programId) {
                candidates[count] = i;
                count++;
            }
            checked++;
        }
        
        // Resize array to actual count
        projectIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            projectIds[i] = candidates[i];
        }
        
        hasMore = (_offset + checked) < nextProjectId;
        return (projectIds, hasMore);
    }
    
    /**
     * @dev Get paginated list of programs by status
     * @param _status Program status to filter by
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of programs to return
     * @return programIds Array of program IDs with the specified status
     * @return hasMore Whether there are more programs
     */
    function getProgramsByStatus(ProgramStatus _status, uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory programIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;
        uint256 checked = 0;
        
        for (uint256 i = _offset; i < nextProgramId && count < _limit; i++) {
            if (getProgramStatus(i) == _status) {
                candidates[count] = i;
                count++;
            }
            checked++;
        }
        
        // Resize array to actual count
        programIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            programIds[i] = candidates[i];
        }
        
        hasMore = (_offset + checked) < nextProgramId;
        return (programIds, hasMore);
    }
    
    /**
     * @dev Get paginated list of projects by status
     * @param _status Project status to filter by
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of projects to return
     * @return projectIds Array of project IDs with the specified status
     * @return hasMore Whether there are more projects
     */
    function getProjectsByStatus(ProjectStatus _status, uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory projectIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;
        uint256 checked = 0;
        
        for (uint256 i = _offset; i < nextProjectId && count < _limit; i++) {
            if (projects[i].status == _status) {
                candidates[count] = i;
                count++;
            }
            checked++;
        }
        
        // Resize array to actual count
        projectIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            projectIds[i] = candidates[i];
        }
        
        hasMore = (_offset + checked) < nextProjectId;
        return (projectIds, hasMore);
    }
    
    /**
     * @dev Get paginated list of programs by host
     * @param _host Host address to filter by
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of programs to return
     * @return programIds Array of program IDs hosted by the specified address
     * @return hasMore Whether there are more programs
     */
    function getProgramsByHost(address _host, uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory programIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        require(_host != address(0), "Invalid host address");
        
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;
        uint256 checked = 0;
        
        for (uint256 i = _offset; i < nextProgramId && count < _limit; i++) {
            if (investmentPrograms[i].host == _host) {
                candidates[count] = i;
                count++;
            }
            checked++;
        }
        
        // Resize array to actual count
        programIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            programIds[i] = candidates[i];
        }
        
        hasMore = (_offset + checked) < nextProgramId;
        return (programIds, hasMore);
    }
    
    /**
     * @dev Get paginated list of projects by owner
     * @param _owner Owner address to filter by
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of projects to return
     * @return projectIds Array of project IDs owned by the specified address
     * @return hasMore Whether there are more projects
     */
    function getProjectsByOwner(address _owner, uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory projectIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        require(_owner != address(0), "Invalid owner address");
        
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;
        uint256 checked = 0;
        
        for (uint256 i = _offset; i < nextProjectId && count < _limit; i++) {
            if (projects[i].owner == _owner) {
                candidates[count] = i;
                count++;
            }
            checked++;
        }
        
        // Resize array to actual count
        projectIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            projectIds[i] = candidates[i];
        }
        
        hasMore = (_offset + checked) < nextProjectId;
        return (projectIds, hasMore);
    }
    
    /**
     * @dev Get paginated list of programs by token
     * @param _token Token address to filter by
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of programs to return
     * @return programIds Array of program IDs using the specified token
     * @return hasMore Whether there are more programs
     */
    function getProgramsByToken(address _token, uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory programIds, bool hasMore) 
    {
        require(_limit <= MAX_PROJECTS_PER_BATCH, "Limit too high");
        
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;
        uint256 checked = 0;
        
        for (uint256 i = _offset; i < nextProgramId && count < _limit; i++) {
            if (investmentPrograms[i].token == _token) {
                candidates[count] = i;
                count++;
            }
            checked++;
        }
        
        // Resize array to actual count
        programIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            programIds[i] = candidates[i];
        }
        
        hasMore = (_offset + checked) < nextProgramId;
        return (programIds, hasMore);
    }
    
    /**
     * @dev Get total count statistics (for pagination planning)
     * @return totalPrograms Total number of programs created
     * @return totalProjects Total number of projects created
     * @return activePrograms Number of currently active programs
     * @return activeProjects Number of currently active projects
     */
    function getTotalCounts() 
        external 
        view 
        returns (
            uint256 totalPrograms,
            uint256 totalProjects,
            uint256 activePrograms,
            uint256 activeProjects
        ) 
    {
        totalPrograms = nextProgramId;
        totalProjects = nextProjectId;
        
        // Count active items (this is expensive, use sparingly)
        for (uint256 i = 0; i < nextProgramId; i++) {
            if (getProgramStatus(i) == ProgramStatus.Active) {
                activePrograms++;
            }
        }
        
        for (uint256 i = 0; i < nextProjectId; i++) {
            if (projects[i].status == ProjectStatus.Active) {
                activeProjects++;
            }
        }
        
        return (totalPrograms, totalProjects, activePrograms, activeProjects);
    }
    
    /**
     * @dev Get lightweight count statistics (for pagination planning)
     * @return totalPrograms Total number of programs created
     * @return totalProjects Total number of projects created
     */
    function getLightweightCounts() 
        external 
        view 
        returns (uint256 totalPrograms, uint256 totalProjects) 
    {
        return (nextProgramId, nextProjectId);
    }
    
    // ===== SIMPLIFIED RECLAIM FUND LOGIC (PRD COMPLIANT) =====
    
    /**
     * @dev Simplified reclaim fund function according to PRD specifications
     * Supporters can reclaim their full investment when:
     * 1. Funding target is not met (project failed)
     * 2. A milestone deadline is missed
     * @param _projectId Project ID to reclaim funds from
     */
    function reclaimFund(uint256 _projectId) 
        external 
        validProject(_projectId) 
        nonReentrant 
        whenNotPaused 
    {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[project.programId];
        
        // Check supporter has investment to reclaim
        uint256 supporterInvestment = project.investments[msg.sender];
        require(supporterInvestment > 0, "No investment to reclaim");
        require(!project.fundsReclaimed, "Funds already reclaimed for this project");
        
        // Check if reclaim is allowed (simple PRD logic)
        bool canReclaim = false;
        string memory reason = "";
        
        // Case 1: Funding target not met after funding period
        if (block.timestamp > program.fundingEndTime) {
            if (project.totalInvested < project.targetFunding) {
                canReclaim = true;
                reason = "Funding target not met";
            }
        }
        
        // Case 2: Project marked as failed due to missed milestones
        // Note: This would be set by milestone module when deadlines are missed
        if (project.status == ProjectStatus.Failed) {
            canReclaim = true;
            reason = "Project failed";
        }
        
        require(canReclaim, "Cannot reclaim funds: project is active or successful");
        
        // Simple reclaim: full investment amount (no proportional deductions)
        uint256 reclaimAmount = supporterInvestment;
        
        // Clear supporter's investment
        project.investments[msg.sender] = 0;
        
        // Transfer full investment back to supporter
        if (program.token == ETH_ADDRESS) {
            (bool sent, ) = payable(msg.sender).call{value: reclaimAmount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(program.token).safeTransfer(msg.sender, reclaimAmount);
        }
        
        emit FundReclaimed(_projectId, msg.sender, reclaimAmount, program.token, reason);
    }
    
    /**
     * @dev Check if a supporter can reclaim funds from a project
     * @param _projectId Project ID to check
     * @param _supporter Supporter address
     * @return canReclaim Whether reclaim is possible
     * @return reason Reason for reclaim eligibility or ineligibility
     * @return amount Amount that can be reclaimed
     */
    function canReclaimFunds(uint256 _projectId, address _supporter) 
        external 
        view 
        validProject(_projectId) 
        returns (bool canReclaim, string memory reason, uint256 amount) 
    {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[project.programId];
        
        uint256 supporterInvestment = project.investments[_supporter];
        
        if (supporterInvestment == 0) {
            return (false, "No investment found", 0);
        }
        
        if (project.fundsReclaimed) {
            return (false, "Funds already reclaimed for this project", 0);
        }
        
        // Check reclaim conditions
        if (block.timestamp > program.fundingEndTime) {
            if (project.totalInvested < project.targetFunding) {
                return (true, "Funding target not met", supporterInvestment);
            }
        }
        
        if (project.status == ProjectStatus.Failed) {
            return (true, "Project failed due to missed milestones", supporterInvestment);
        }
        
        return (false, "Project is active or successful", 0);
    }
    
    /**
     * @dev Batch reclaim funds for multiple projects (gas optimized)
     * @param _projectIds Array of project IDs to reclaim from
     */
    function batchReclaimFunds(uint256[] calldata _projectIds) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        require(_projectIds.length <= MAX_PROJECTS_PER_BATCH, "Too many projects in batch");
        
        for (uint256 i = 0; i < _projectIds.length; i++) {
            if (_projectIds[i] < nextProjectId) {
                _internalReclaimFund(_projectIds[i]);
            }
        }
    }
    
    /**
     * @dev Internal reclaim function to avoid reentrancy issues in batch operations
     * @param _projectId Project ID to reclaim from
     */
    function _internalReclaimFund(uint256 _projectId) internal {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[project.programId];
        
        // Check supporter has investment to reclaim
        uint256 supporterInvestment = project.investments[msg.sender];
        if (supporterInvestment == 0 || project.fundsReclaimed) {
            return; // Skip if no investment or already reclaimed
        }
        
        // Check if reclaim is allowed (simple PRD logic)
        bool canReclaim = false;
        string memory reason = "";
        
        // Case 1: Funding target not met after funding period
        if (block.timestamp > program.fundingEndTime) {
            if (project.totalInvested < project.targetFunding) {
                canReclaim = true;
                reason = "Funding target not met";
            }
        }
        
        // Case 2: Project marked as failed due to missed milestones
        if (project.status == ProjectStatus.Failed) {
            canReclaim = true;
            reason = "Project failed";
        }
        
        if (!canReclaim) {
            return; // Skip if can't reclaim
        }
        
        // Simple reclaim: full investment amount (no proportional deductions)
        uint256 reclaimAmount = supporterInvestment;
        
        // Clear supporter's investment
        project.investments[msg.sender] = 0;
        
        // Transfer full investment back to supporter
        if (program.token == ETH_ADDRESS) {
            (bool sent, ) = payable(msg.sender).call{value: reclaimAmount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(program.token).safeTransfer(msg.sender, reclaimAmount);
        }
        
        emit FundReclaimed(_projectId, msg.sender, reclaimAmount, program.token, reason);
    }
    
    /**
     * @dev Mark a project as failed (only callable by milestone module or admin)
     * This enables reclaim functionality when milestones are missed
     * @param _projectId Project ID to mark as failed
     * @param _reason Reason for failure
     */
    function markProjectAsFailed(uint256 _projectId, string memory _reason) 
        external 
        validProject(_projectId) 
        onlyOwnerOrAdmin 
    {
        Project storage project = projects[_projectId];
        require(project.status != ProjectStatus.Failed, "Project already failed");
        require(project.status != ProjectStatus.Successful, "Cannot fail successful project");
        
        ProjectStatus oldStatus = project.status;
        project.status = ProjectStatus.Failed;
        
        emit ProjectStatusChanged(_projectId, oldStatus, ProjectStatus.Failed);
        emit ProjectMarkedAsFailed(_projectId, _reason);
    }
    
    // ===== ADDITIONAL EVENTS FOR RECLAIM FUNCTIONALITY =====
    
    event FundReclaimed(
        uint256 indexed projectId,
        address indexed supporter,
        uint256 amount,
        address token,
        string reason
    );
    
    event ProjectMarkedAsFailed(
        uint256 indexed projectId,
        string reason
    );
    
    // ===== BASIC INVESTMENT FUNCTIONS FOR TESTING =====
    
    /**
     * @dev Basic investment function for testing the reclaim functionality
     * Note: In production, this would be in the funding module
     * @param _projectId Project ID to invest in
     */
    function investFund(uint256 _projectId) 
        external 
        payable 
        validProject(_projectId) 
        nonReentrant 
        whenNotPaused 
    {
        Project storage project = projects[_projectId];
        InvestmentProgram storage program = investmentPrograms[project.programId];
        
        require(msg.value >= MIN_INVESTMENT_AMOUNT, "Investment amount must be greater than 0");
        require(program.token == ETH_ADDRESS, "This function only supports ETH investments");
        require(block.timestamp >= program.fundingStartTime, "Funding not started");
        require(block.timestamp <= program.fundingEndTime, "Funding ended");
        
        // Update investment tracking
        project.investments[msg.sender] += msg.value;
        project.totalInvested += msg.value;
        
        if (project.investments[msg.sender] == msg.value) {
            // First time investor
            project.supporterCount++;
        }
        
        emit FundInvested(_projectId, msg.sender, msg.value, program.token);
    }
    
    event FundInvested(
        uint256 indexed projectId,
        address indexed supporter,
        uint256 amount,
        address token
    );
}