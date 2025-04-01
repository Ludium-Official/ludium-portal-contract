// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LdEduProgram is Ownable, ReentrancyGuard {

    // 이벤트 정의
    event ProgramCreated(uint256 indexed id, address indexed maker, address indexed validator, uint256 price);
    event ProgramApproved(uint256 indexed id, address builder);
    event ProposalSubmitted(uint256 indexed programId, uint256 proposalId, address builder);
    event MilestoneSubmitted(uint256 indexed id, uint256 milestoneId, string[] links);
    event MilestoneApproved(uint256 indexed id, uint256 milestoneId, uint256 reward);
    event ProgramClaimed(uint256 indexed id, address builder, uint256 amount);
    event FundsReclaimed(uint256 indexed id, address maker, uint256 amount);
    event ValidatorUpdated(uint256 indexed id, address newValidator);
    event FeeUpdated(uint256 newFee);

    // 그랜츠 프로그램 구조체 (EduProgram)
    struct EduProgram {
        uint256 id;
        string name;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        address maker;
        address validator;
        bool approve;
        bool claimed;
        address builder;
    }

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

    enum ProposalStatus { Applied, Denied, Selected }

    struct Proposal {
        uint256 id;
        address builder;
        string[] milestoneNames;
        string[] milestoneDescriptions;
        uint256[] milestonePrices;
        ProposalStatus status;
    }

    struct ValAddr {
        uint256 programId;
        bool isValidator;
    }

    mapping(uint256 => EduProgram) public eduPrograms;
    mapping(uint256 => Proposal[]) public programProposals;
    mapping(uint256 => Milestone[]) public programMilestones;
    mapping(uint256 => uint256) public selectedProposalIndex;
    mapping(uint256 => uint256) public nextProposalId;
    mapping(uint256 => uint256) public nextMilestoneId;

    uint256 public nextProgramId;
    uint256 private fee;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice 프로그램 생성 함수
     */
    function createEduProgram(
        string memory _name,
        uint256 _price,
        uint256 _startTime,
        uint256 _endTime,
        address _validator
    ) external payable {
        require(msg.value == _price, "The ETH sent does not match the program price");
        require(_startTime < _endTime, "The Start time must be earlier than the end time.");
        uint256 programId = nextProgramId;

        eduPrograms[programId] = EduProgram({
            id: programId,
            name: _name,
            price: _price,
            startTime: _startTime,
            endTime: _endTime,
            maker: msg.sender,
            validator: _validator,
            approve: false,
            claimed: false,
            builder: address(0)
        });
        nextProgramId++;
        emit ProgramCreated(programId, msg.sender, _validator, _price);
    }

    /**
     * @notice 벨리데이터가 프로그램을 승인하는 함수
     */
    function approveProgram(uint256 programId, address _builder) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "You don't have approval permissions.");
        require(block.timestamp <= program.endTime, "The program has already ended. ");
        require(!program.approve, "Already approved.");
        program.approve = true;
        program.builder = _builder;

        emit ProgramApproved(programId, _builder);
    }

    /**
     * @notice 빌더가 프로그램에 대한 제안서를 제출하는 함수
     */
    function submitProposal(
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

        uint256 proposalId = nextProposalId[programId]++;

        Proposal memory p = Proposal({
            id: proposalId,
            builder: msg.sender,
            milestoneNames: names,
            milestoneDescriptions: descriptions,
            milestonePrices: prices,
            status: ProposalStatus.Applied
        });

        programProposals[programId].push(p);
        emit ProposalSubmitted(programId, proposalId, msg.sender);
    }

    /**
     * @notice 벨리데이터가 Proposal을 선택 또는 거절하는 함수
     */
    function evaluateProposal(uint256 programId, uint256 proposalId, bool isSelected) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "Not validator");

        Proposal[] storage proposals = programProposals[programId];
        bool found = false;

        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i].id == proposalId) {
                Proposal storage proposal = proposals[i];
                require(proposal.status == ProposalStatus.Applied, "Already evaluated");

                if (isSelected) {
                    require(program.builder == address(0), "Already selected");
                    proposal.status = ProposalStatus.Selected;
                    program.builder = proposal.builder;
                    program.approve = true;
                    selectedProposalIndex[programId] = i;

                    for (uint256 j = 0; j < proposal.milestoneNames.length; j++) {
                        uint256 milestoneId = nextMilestoneId[programId]++;
                        programMilestones[programId].push(Milestone({
                            id: milestoneId,
                            name: proposal.milestoneNames[j],
                            description: proposal.milestoneDescriptions[j],
                            price: proposal.milestonePrices[j],
                            submitted: false,
                            approved: false,
                            claimed: false,
                            links: new string[](0)
                        }));
                    }
                    emit ProgramApproved(programId, proposal.builder);
                } else {
                    proposal.status = ProposalStatus.Denied;
                }
                found = true;
                break;
            }
        }
        require(found, "Proposal ID not found");
    }

    /**
     * @notice 빌더가 마일스톤 결과를 제출하는 함수
     */
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

    /**
     * @notice 벨리데이터가 마일스톤을 승인하고 보상을 지급하는 함수
     */
    function approveMilestone(uint256 programId, uint256 milestoneId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "Not validator");

        Milestone storage m = programMilestones[programId][milestoneId];
        require(m.submitted, "Not submitted");
        require(!m.approved && !m.claimed, "Already handled");

        m.approved = true;
        m.claimed = true;

        (bool sent, ) = payable(program.builder).call{value: m.price}("");
        require(sent, "ETH transfer failed");

        emit MilestoneApproved(programId, milestoneId, m.price);
        emit ProgramClaimed(programId, program.builder, m.price);
    }

    /**
     * @notice 프로그램 기간 만료 후, 아직 승인되지 않은 경우 제작자가 예치금을 회수하는 함수
     */
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

    /**
     * @notice 제작자가 승인 벨리데이터를 변경하는 함수
     */
    function updateValidator(uint256 programId, address newValidator) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.maker, "Only creators can change approvers.");
        program.validator = newValidator;

        emit ValidatorUpdated(programId, newValidator);
    }

    /**
     * @notice 계약 소유자가 수수료를 설정하는 함수
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
        emit FeeUpdated(_fee);
    }

    /**
     * @notice 현재 설정된 수수료를 반환하는 함수
     */
    function getFee() external view returns (uint256) {
        return fee;
    }
} 
