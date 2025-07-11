// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LdEduProgram is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event ProgramCreated(
        uint256 indexed id,
        address indexed maker,
        address indexed validator,
        uint256 price,
        address token
    );
    event MilestoneAccepted(
        uint256 indexed programId,
        address indexed builder,
        uint256 reward,
        address token
    );
    event FundsReclaimed(
        uint256 indexed id,
        address maker,
        uint256 amount,
        address token
    );
    event ProgramEdited(
        uint256 programId,
        uint256 price,
        uint256 startTime,
        uint256 endTime,
        address newValidator
    );
    event FeeUpdated(uint256 newFee);
    event TokenWhitelisted(address token, bool status);

    struct EduProgram {
        uint256 id;
        string name;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        address maker;
        address validator;
        bool claimed;
        bool approve;
        address token; // 토큰 주소 (address(0)이면 ETH)
    }

    struct Milestone {
        uint256 id;
        string name;
        string description;
        uint256 price;
        string[] links;
        uint256 applicationId;
    }

    mapping(uint256 => EduProgram) public eduPrograms;
    mapping(address => bool) public whitelistedTokens; // 허용된 토큰들
    uint256 public nextProgramId;
    uint256 private fee;

    // ETH를 나타내는 상수
    address public constant ETH_ADDRESS = address(0);

    constructor(address initialOwner) Ownable(initialOwner) {
        // ETH는 기본적으로 허용
        whitelistedTokens[ETH_ADDRESS] = true;
    }

    // 토큰 화이트리스트 관리
    function setTokenWhitelist(address token, bool status) external onlyOwner {
        whitelistedTokens[token] = status;
        emit TokenWhitelisted(token, status);
    }

    function createEduProgram(
        string memory _name,
        uint256 _price,
        uint256 _startTime,
        uint256 _endTime,
        address _validator,
        address _token //토큰 주소, eth의 경우 address(0)
    ) external payable {
        require(whitelistedTokens[_token], "Token not whitelisted");
        require(
            _startTime < _endTime,
            "The Start time must be earlier than the end time."
        );
        require(_price > 0, "Price must be greater than 0");

        uint256 programId = nextProgramId;

        if (_token == ETH_ADDRESS) {
            // ETH 결제
            require(
                msg.value == _price,
                "The ETH sent does not match the program price"
            );
        } else {
            // ERC-20 토큰 결제
            require(
                msg.value == 0,
                "Should not send ETH when paying with token"
            );
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _price);
        }

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
            token: _token
        });

        nextProgramId++;
        emit ProgramCreated(programId, msg.sender, _validator, _price, _token);
    }

    function acceptMilestone(
        uint256 programId,
        address builder,
        uint256 reward
    ) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "Not validator");
        require(reward <= program.price, "Reward exceeds program balance");

        if (program.token == ETH_ADDRESS) {
            // ETH 전송
            require(
                address(this).balance >= reward,
                "Insufficient contract ETH balance"
            );
            (bool sent, ) = payable(builder).call{value: reward}("");
            require(sent, "ETH transfer failed");
        } else {
            // ERC-20 토큰 전송
            IERC20 token = IERC20(program.token);
            require(
                token.balanceOf(address(this)) >= reward,
                "Insufficient contract token balance"
            );
            token.safeTransfer(builder, reward);
        }

        program.price -= reward;
        emit MilestoneAccepted(programId, builder, reward, program.token);
    }

    function reclaimFunds(uint256 programId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(block.timestamp > program.endTime, "Program not ended yet");
        require(msg.sender == program.maker, "Not the program maker");
        require(!program.claimed, "Already claimed");

        uint256 remainingAmount = program.price;
        require(remainingAmount > 0, "No funds to reclaim");

        program.claimed = true;
        program.price = 0; // 중복 인출 방지

        if (program.token == ETH_ADDRESS) {
            (bool sent, ) = payable(program.maker).call{value: remainingAmount}(
                ""
            );
            require(sent, "ETH transfer failed");
        } else {
            // ERC-20 토큰 반환
            IERC20(program.token).safeTransfer(program.maker, remainingAmount);
        }

        emit FundsReclaimed(
            programId,
            program.maker,
            remainingAmount,
            program.token
        );
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

    // 긴급상황 시 토큰 회수 (관리자 전용)
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

    // 컨트랙트의 토큰 잔액 조회
    function getContractBalance(address token) external view returns (uint256) {
        if (token == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    // 편의 함수들
    function getProgramDetails(
        uint256 programId
    )
        external
        view
        returns (
            string memory name,
            uint256 price,
            address maker,
            address validator,
            address token,
            bool claimed
        )
    {
        EduProgram storage program = eduPrograms[programId];
        return (
            program.name,
            program.price,
            program.maker,
            program.validator,
            program.token,
            program.claimed
        );
    }
}
