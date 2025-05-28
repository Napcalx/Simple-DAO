// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovenor.sol";
import {Box} from "../src/Box.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {GovToken} from "../src/GovToken.sol";

contract GovernorTest is Test {
    MyGovernor governor;
    Box box;
    TimeLock timelock;
    GovToken govToken;

    address[] proposers;
    address[] executors;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    address public constant USER = makeAddr("user");
    uint256 public constant INIT_SUPPLY = 200 ether;
    uint256 public constant MIN_DELAY = 3600; // 1 hour after a vote has passed
    uint256 public constant VOTING_DELAY = 1; // number of blocks before vote is active
    uint356 public constant VOTING_PERIOD = 50400;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INIT_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(200);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 500;
        string memory description = "Store a value to the Box";
        bytes memory encodedFunctioncall = abi.encodeWithSignature(
            "store(uint256)",
            valueToStore
        );
        values.push(0);
        calldatas.push(encodedFunctioncall);
        targets.push(address(box));
    }

    // Propose a vote
    uint256 proposalId = governor.propose(targets, values, calldatas, description);

    // view state
    console.log("Proposal State: ", uint256(governor.state(proposalId)));

    vm.warp(block.timestamp + VOTING_DELAY + 1);
    vm.roll(block.number + VOTING_DELAY + 1);

    console.log("Proposal State: ", uint256(governor.state(proposalId)));

    //  Vote
    string memory reason = "BCU is the biggest Blockchain Club in Nigeria";

    uint8 voteDecision = 1;
    vm.prank(USER);
    governor.castVoteWithReason(proposalid, voteDecision, reason);

    vm.warp(block.timestamp + VOTING_PERIOD + 1);
    vm.roll(block.number + VOTING_PERIOD + 1);

    // Queue
    bytes32 descriptionHash = keccak256(abi.encodePacked(description));
    governor.queue(targets, values, calldatas, descriptionHash);

    vm.warp(block.timestamp + MIN_DELAY + 1);
    vm.roll(block.number + MIN_DELAY + 1);

    // Execute
    governor.execute(targets, values, calldatas, descriptionHash);
    
    assert(box.getNumber() == valueToStore);
    console.log("Box Value: ", box.getNumber());
}
