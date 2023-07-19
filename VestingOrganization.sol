// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error InvalidAddress();
error InvalidCaller();
error ArraySizeMismatch();

contract VestingOrganization is OwnableUpgradeable {

    using SafeERC20 for IERC20;

    struct VestingPlan {
        bool eligible;
        bool[] portionAvailability;
        uint256[] portionAmounts;
        uint256[] portionTimestamps;
    }

    IERC20 public token;
    mapping(address => VestingPlan) public vestingPlans;

    function initialize(
        address _token
    ) external initializer {
        // Set organization manager as owner
        __Ownable_init();
        // Check and set token
        if (_token == address(0)) {
            revert InvalidAddress();
        }
        token = IERC20(_token);
    }

    function addParticipants(
        address[] memory participants,
        uint256[] memory _portionAmounts,
        uint256[] memory _portionTimestamps
    ) external onlyOwner { 
        // Gas optimization 
        uint256 length = _portionAmounts.length; 
        if (length != _portionTimestamps.length) { 
            revert ArraySizeMismatch(); 
        }
        bool[] memory _portionAvailability = new bool[](length);
        uint i;
        for (; i < length; i++) {
            _portionAvailability[i] = true;
        }
        for (i = 0; i < participants.length; i++) {
            vestingPlans[participants[i]] = VestingPlan({
                eligible: true,
                portionAvailability: _portionAvailability,
                portionAmounts: _portionAmounts,
                portionTimestamps: _portionTimestamps
            });
        }
    }

    function withdraw(address participant, uint256[] calldata portions) external onlyOwner returns (uint256) {
        VestingPlan memory vp = vestingPlans[participant];
        if (!vp.eligible) {
            revert InvalidCaller();
        }
        uint256 amountToWithdraw;
        for (uint i; i < portions.length; i++) {
            if (
                vp.portionAvailability[i] && block.timestamp >= vp.portionTimestamps[i]
            ) {
                vp.portionAvailability[i] = false;
                amountToWithdraw += vp.portionAmounts[i];
            }
        }
        if (amountToWithdraw > 0)
            token.safeTransfer(participant, amountToWithdraw);
        return amountToWithdraw;
    }

    function removeParticipant(address participant) external onlyOwner {
        if (vestingPlans[participant].eligible)
            vestingPlans[participant].eligible = false;
    }

    function depositTokens(uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
    }
}
