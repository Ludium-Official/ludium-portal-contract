// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILdFunding
 * @dev Interface for investment and funding operations
 */
interface ILdFunding {
    // Events
    event FundInvested(
        uint256 indexed projectId,
        address indexed supporter,
        uint256 amount,
        address token
    );
    
    event FundReclaimed(
        uint256 indexed projectId,
        address indexed owner,
        uint256 amount,
        address token
    );
    
    event FeeClaimed(
        uint256 indexed programId,
        address indexed host,
        uint256 amount,
        address token
    );
    
    // Functions
    function investFund(uint256 _projectId) external payable;
    function investWithToken(uint256 _projectId, uint256 _amount) external;
    function reclaimFund(uint256 _projectId) external;
    function feeClaim(uint256 _programId) external;
    
    function getInvestmentAmount(uint256 _projectId, address _supporter) external view returns (uint256);
    function getTotalInvestment(uint256 _projectId) external view returns (uint256);
    function isUserEligibleToInvest(uint256 _projectId, address _user, uint256 _amount) external view returns (bool eligible, string memory reason);
}