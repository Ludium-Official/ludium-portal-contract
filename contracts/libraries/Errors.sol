// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Errors
 * @dev Standardized error codes and messages for Ludium Investment Program
 */
library Errors {
    // Error codes (E1xxx - E9xxx)
    
    // E1xxx - Validation Errors
    error InvalidProgramId(uint256 programId); // E1001
    error InvalidProjectId(uint256 projectId); // E1002
    error InvalidValidatorAddress(address validator); // E1003
    error InvalidHostAddress(address host); // E1004
    error InvalidOwnerAddress(address owner); // E1005
    error InvalidTokenAddress(address token); // E1006
    error EmptyProgramName(); // E1007
    error EmptyProjectName(); // E1008
    error EmptyMilestoneTitle(); // E1009
    error InvalidApprovalCount(uint256 required, uint256 available); // E1010
    
    // E2xxx - Timing Errors
    error ApplicationNotStarted(uint256 currentTime, uint256 startTime); // E2001
    error ApplicationEnded(uint256 currentTime, uint256 endTime); // E2002
    error FundingNotStarted(uint256 currentTime, uint256 startTime); // E2003
    error FundingEnded(uint256 currentTime, uint256 endTime); // E2004
    error InvalidTimeRange(uint256 startTime, uint256 endTime); // E2005
    error InvalidApplicationTime(uint256 startTime); // E2006
    error InvalidMilestoneDeadline(uint256 deadline, uint256 fundingEnd); // E2007
    
    // E3xxx - Permission Errors
    error NotValidator(address caller); // E3001
    error NotProgramManager(address caller); // E3002
    error NotTokenManager(address caller); // E3003
    error NotPauserRole(address caller); // E3004
    error NotOwnerOrAdmin(address caller); // E3005
    error NotAuthorizedForRole(address caller, bytes32 role); // E3006
    
    // E4xxx - Limit Errors
    error TooManyValidators(uint256 count, uint256 max); // E4001
    error TooManyProjects(uint256 count, uint256 max); // E4002
    error TooManyRequiredApprovals(uint256 count); // E4003
    error FeePercentageTooHigh(uint256 fee, uint256 max); // E4004
    error FeePercentageExceedsLimit(uint256 fee); // E4005
    error TargetFundingExceedsLimit(uint256 target, uint256 max); // E4006
    error MilestonePercentageExceedsLimit(uint256 percentage); // E4007
    error InvalidMilestonePercentage(uint256 percentage); // E4008
    error InvalidTotalPercentage(uint256 total, uint256 expected); // E4009
    
    // E5xxx - Investment Errors
    error InsufficientInvestment(uint256 amount, uint256 minimum); // E5001
    error NoInvestmentToReclaim(address investor); // E5002
    error FundsAlreadyReclaimed(uint256 projectId); // E5003
    error CannotReclaimFunds(string reason); // E5004
    error TokenNotWhitelisted(address token); // E5005
    error UnsupportedToken(address token); // E5006
    error TransferFailed(address token, address to, uint256 amount); // E5007
    
    // E6xxx - Status Errors
    error ProjectAlreadyFailed(uint256 projectId); // E6001
    error CannotFailSuccessfulProject(uint256 projectId); // E6002
    error ProjectNotEligibleForReclaim(uint256 projectId, string status); // E6003
    
    // E7xxx - Pagination Errors
    error LimitTooHigh(uint256 limit, uint256 max); // E7001
    error OffsetOutOfBounds(uint256 offset, uint256 total); // E7002
    error IndexOutOfBounds(uint256 index, uint256 length); // E7003
    
    // E8xxx - Batch Operation Errors
    error BatchSizeTooLarge(uint256 size, uint256 max); // E8001
    error EmptyBatch(); // E8002
    
    // E9xxx - System Errors
    error ContractPaused(); // E9001
    error ContractNotPaused(); // E9002
    error ZeroAddress(); // E9003
    error InvalidConfiguration(); // E9004
    error OperationNotAllowed(); // E9005
    
    // Error message functions for backwards compatibility
    function programIdError(uint256 programId) internal pure returns (string memory) {
        return string(abi.encodePacked("E1001: Invalid program ID ", _toString(programId)));
    }
    
    function projectIdError(uint256 projectId) internal pure returns (string memory) {
        return string(abi.encodePacked("E1002: Invalid project ID ", _toString(projectId)));
    }
    
    function validatorError(address validator) internal pure returns (string memory) {
        return string(abi.encodePacked("E1003: Invalid validator address ", _toHexString(validator)));
    }
    
    function hostError(address host) internal pure returns (string memory) {
        return string(abi.encodePacked("E1004: Invalid host address ", _toHexString(host)));
    }
    
    function ownerError(address owner) internal pure returns (string memory) {
        return string(abi.encodePacked("E1005: Invalid owner address ", _toHexString(owner)));
    }
    
    function tokenError(address token) internal pure returns (string memory) {
        return string(abi.encodePacked("E1006: Invalid token address ", _toHexString(token)));
    }
    
    // Helper functions
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            buffer[2 + i * 2] = _HEX_SYMBOLS[uint8(bytes20(addr)[i]) >> 4];
            buffer[3 + i * 2] = _HEX_SYMBOLS[uint8(bytes20(addr)[i]) & 0x0f];
        }
        return string(buffer);
    }
    
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
}