// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LdEduProgram is Ownable, ReentrancyGuard {
    event ProgramCreated(uint256 indexed id, address indexed maker, address indexed validator, uint256 price);
    event MilestoneAccepted(uint256 indexed programId, address indexed builder, uint256 reward);
    event FundsReclaimed(uint256 indexed id, address maker, uint256 amount);
    event ProgramEdited(uint256 programId, uint256 price, uint256 startTime, uint256 endTime, address newValidator);
    event FeeUpdated(uint256 newFee);

    struct EduProgram {
        uint256 id;
        string name;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        address maker;
        address validator;
        bool claimed;
    }


    mapping(uint256 => EduProgram) public eduPrograms;
    uint256 public nextProgramId;
    uint256 private fee;

    constructor(address initialOwner) Ownable() {
    _transferOwnership(initialOwner);
    }


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
            claimed: false
        });
        nextProgramId++;
        emit ProgramCreated(programId, msg.sender, _validator, _price);
    }


    function acceptMilestone(
        uint256 programId,
        address builder,
        uint256 reward
    ) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "Not validator");
        require(reward <= program.price, "Reward exceeds program balance");
        require(address(this).balance >= reward, "Insufficient contract balance");

        (bool sent, ) = payable(builder).call{value: reward}("");
        require(sent, "Transfer failed");
        program.price -= reward; 

        emit MilestoneAccepted(programId, builder, reward);
    }


    function reclaimFunds(uint256 programId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
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
