// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LdEduProgram is Ownable, ReentrancyGuard {
    event ProgramCreated(uint256 indexed id, address indexed maker, address indexed validator, uint256 price);
    event ProgramApproved(uint256 indexed programId);
    event ProgramApplied(uint256 indexed id);
    event SelectedApplication(uint256 indexed programId, uint256 applicationId, address builder);
    event MilestoneSubmitted(uint256 indexed id, uint256 milestoneId, string[] links);
    event MilestoneAccepted(uint256 indexed id, uint256 milestoneId, uint256 reward);
    event ProgramClaimed(uint256 indexed id, address builder, uint256 amount);
    event FundsReclaimed(uint256 indexed id, address maker, uint256 amount);
    event ProgramEdited(uint256 programId, uint256 price, uint256 startTime, uint256 endTime, address newValidator);
    event FeeUpdated(uint256 newFee);

    struct EduProgram {
        uint256 id;
        string name;
        string keywords;
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
        string[] milestoneNames;
        string[] milestoneDescriptions;
        uint256[] milestonePrices;
        ApplicationStatus status;
    }

    enum ApplicationStatus { Applied, Denied, Selected }

    struct Milestone {
        uint256 id;
        string name;
        string description;
        uint256 price;
        bool submitted;
        bool approved;
        bool claimed;
        string[] links;
    }

    mapping(uint256 => EduProgram) public eduPrograms;
    mapping(uint256 => Application[]) public programApplications;
    mapping(uint256 => Milestone[]) public programMilestones;
    mapping(uint256 => uint256) public selectedApplicationIndex;
    mapping(uint256 => uint256) public nextApplicationId;
    mapping(uint256 => uint256) public nextMilestoneId;

    uint256 public nextProgramId;
    uint256 private fee;

    constructor(address initialOwner) Ownable() {
        _transferOwnership(initialOwner);
    }

    function createEduProgram(
        string memory _name,
        uint256 _price,
        string memory _keywords,
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
        require(msg.sender == program.validator, "You don't have approval permissions.");
        require(block.timestamp <= program.endTime, "The program has already ended.");
        require(!program.approve, "Already approved.");
        program.approve = true;
        emit ProgramApproved(programId);
    }

    function submitApplication(
        uint256 programId,
        string[] calldata names,
        string[] calldata descriptions,
        uint256[] calldata prices
    ) external {
        EduProgram storage program = eduPrograms[programId];
        require(block.timestamp < program.endTime, "Program ended");
        require(names.length == descriptions.length && names.length == prices.length, "Input mismatch");

        uint256 total;
        for (uint256 i = 0; i < prices.length; i++) {
            total += prices[i];
        }
        require(total == program.price, "Milestone total != program price");

        uint256 applicationId = nextApplicationId[programId]++;

        Application memory a = Application({
            id: applicationId,
            builder: msg.sender,
            milestoneNames: names,
            milestoneDescriptions: descriptions,
            milestonePrices: prices,
            status: ApplicationStatus.Applied
        });

        programApplications[programId].push(a);
        emit ProgramApplied(applicationId);
    }

    function selectApplication(uint256 programId, uint256 applicationId, bool isSelected) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "Not validator");

        Application[] storage applications = programApplications[programId];
        bool found = false;

        for (uint256 i = 0; i < applications.length; i++) {
            if (applications[i].id == applicationId) {
                Application storage app = applications[i];
                require(app.status == ApplicationStatus.Applied, "Already evaluated");

                if (isSelected) {
                    require(program.builder == address(0), "Already selected");
                    app.status = ApplicationStatus.Selected;
                    program.builder = app.builder;
                    program.approve = true;
                    selectedApplicationIndex[programId] = i;

                    for (uint256 j = 0; j < app.milestoneNames.length; j++) {
                        uint256 milestoneId = nextMilestoneId[programId]++;
                        programMilestones[programId].push(Milestone({
                            id: milestoneId,
                            name: app.milestoneNames[j],
                            description: app.milestoneDescriptions[j],
                            price: app.milestonePrices[j],
                            submitted: false,
                            approved: false,
                            claimed: false,
                            links: new string[](0)
                        }));
                    }
                    emit SelectedApplication(programId, applicationId, app.builder);
                } else {
                    app.status = ApplicationStatus.Denied;
                }
                found = true;
                break;
            }
        }
        require(found, "Proposal ID not found");
    }

    function submitMilestone(uint256 programId, uint256 milestoneId, string[] calldata links) external {
        EduProgram storage program = eduPrograms[programId];
        require(program.approve, "Not approved");
        require(msg.sender == program.builder, "Not selected builder");

        Milestone storage m = programMilestones[programId][milestoneId];
        require(!m.submitted, "Already submitted");

        m.submitted = true;
        m.links = links;
        emit MilestoneSubmitted(programId, milestoneId, links);
    }

    function acceptMilestone(uint256 programId, uint256 milestoneId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "Not validator");

        Milestone storage m = programMilestones[programId][milestoneId];
        require(m.submitted, "Not submitted");
        require(!m.approved && !m.claimed, "Already handled");

        m.approved = true;
        m.claimed = true;

        (bool sent, ) = payable(program.builder).call{value: m.price}("");
        require(sent, "ETH transfer failed");

        emit MilestoneAccepted(programId, milestoneId, m.price);
        emit ProgramClaimed(programId, program.builder, m.price);
    }

    function reclaimFunds(uint256 programId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(!program.approve, "It's already been approved and can't be reclaimed.");
        require(!program.claimed, "Already taken care of.");
        require(block.timestamp > program.endTime, "The program hasn't ended yet.");
        require(msg.sender == program.maker, "You don't have reclamation rights.");

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
        require(msg.sender == program.maker, "Only creators can edit the program.");
        require(startTime < endTime, "Start time must be before end time.");
        require(price > 0, "Price must be positive.");

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