// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LdEduProgram is Ownable, ReentrancyGuard {
    event ProgramCreated(uint256 indexed id, address indexed maker, address indexed validator, uint256 price);
    event ProgramApproved(uint256 indexed programId);
    event ProgramApplied(uint256 indexed applicationId, uint256[] milestoneIds );
    event ApplicationSelected(uint256 indexed applicationId, address indexed builder);
    event ApplicationDenied(uint256 indexed applicationId);
    event MilestoneSubmitted( uint256 indexed milestoneId);
    event MilestoneAccepted(uint256 indexed milestoneId, uint256 reward);
    event MilestoneRejected( uint256 indexed milestoneId);
    event ProgramClaimed(uint256 indexed id, address builder, uint256 amount);
    event FundsReclaimed(uint256 indexed id, address maker, uint256 amount);
    event ProgramEdited(uint256 programId, uint256 price, uint256 startTime, uint256 endTime, address newValidator);
    event FeeUpdated(uint256 newFee);

    struct EduProgram {
        uint256 id;
        string name;
        string[] keywords;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        string summary;
        string description;
        string[] links;
        address maker;
        address validator;
        bool approve;
        bool claimed;
        address builder;
    }

    struct Application {
        uint256 id;
        address builder;
        uint256 programId;
        ApplicationStatus status;
    }

    struct MilestoneInput {
        string name;
        string description;
        uint256 price;
    }

    struct Milestone {
        uint256 id;
        string name;
        string description;
        uint256 price;
        string[] links;
        uint256 applicationId;
        MilestoneStatus status;
    }

    enum ApplicationStatus { Applied, Denied, Selected }
    enum MilestoneStatus { NotSubmitted, Submitted, Accepted, Rejected }

    mapping(uint256 => EduProgram) public eduPrograms;
    mapping(uint256 => Application) public applications;
    mapping(uint256 => Milestone) public milestones;
    uint256 public nextApplicationId;
    uint256 public nextMilestoneId;
    uint256 public nextProgramId;
    uint256 private fee;

    constructor(address initialOwner) Ownable() {
    _transferOwnership(initialOwner);
    }


    function createEduProgram(
        string memory _name,
        uint256 _price,
        string [] memory _keywords,
        uint256 _startTime,
        uint256 _endTime,
        address _validator,
        string memory _summary,
        string memory _description,
        string[] memory _links
    ) external payable {
        require(msg.value == _price, "The ETH sent does not match the program price");
        require(_startTime < _endTime, "The Start time must be earlier than the end time.");

        uint256 programId = nextProgramId;

        eduPrograms[programId] = EduProgram({
            id: programId,
            name: _name,
            keywords: _keywords,
            price: _price,
            startTime: _startTime,
            endTime: _endTime,
            summary: _summary,
            description: _description,
            links: _links,
            maker: msg.sender,
            validator: _validator,
            approve: false,
            claimed: false,
            builder: address(0)
        });
        nextProgramId++;
        emit ProgramCreated(programId, msg.sender, _validator, _price);
    }

    function approveProgram(uint256 programId) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "Not validator");
        require(block.timestamp <= program.endTime, "Program ended");
        require(!program.approve, "Already approved");

        program.approve = true;
        emit ProgramApproved(programId);
    }


    function acceptMilestone(uint256 milestoneId) external nonReentrant {
        Milestone storage m = milestones[milestoneId];
        Application storage app = applications[m.applicationId];
        EduProgram storage program = eduPrograms[app.programId];

        require(msg.sender == program.validator, "Not validator");
        require(m.status == MilestoneStatus.Submitted, "Invalid status");

        m.status = MilestoneStatus.Accepted;

        (bool sent, ) = payable(program.builder).call{value: m.price}("");
        require(sent, "ETH transfer failed");

        emit MilestoneAccepted(milestoneId, m.price);
        emit ProgramClaimed(program.id, program.builder, m.price);
    }

    function rejectMilestone(uint256 milestoneId) external {
        Milestone storage m = milestones[milestoneId];
        Application storage app = applications[m.applicationId];
        EduProgram storage program = eduPrograms[app.programId];

        require(msg.sender == program.validator, "Not validator");
        require(m.status == MilestoneStatus.Submitted, "Invalid status");

        m.status = MilestoneStatus.Rejected;

        emit MilestoneRejected(milestoneId);
    }


    function reclaimFunds(uint256 programId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(!program.approve, "Already approved");
        require(!program.claimed, "Already claimed");
        require(block.timestamp > program.endTime, "Program not ended yet");
        require(msg.sender == program.maker, "Not the program maker");

        program.claimed = true;
        payable(program.maker).transfer(program.price);

        emit FundsReclaimed(programId, program.maker, program.price);
    }

    function updateProgram(
        uint256 programId,
        uint256 price,
        uint256 startTime,
        uint256 endTime,
        address newValidator
    ) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.maker, "Only creator");
        require(startTime < endTime, "Invalid time");
        require(price > 0, "Invalid price");

        program.price = price;
        program.startTime = startTime;
        program.endTime = endTime;
        program.validator = newValidator;

        emit ProgramEdited(programId, price, startTime, endTime, newValidator);
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
        emit FeeUpdated(_fee);
    }

    function getFee() external view returns (uint256) {
        return fee;
    }
}
