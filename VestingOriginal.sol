// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error TimeLockClosed();
error InvalidSettings();
error InvalidCaller();

contract VestingOrganization is OwnableUpgradeable {

    using SafeERC20 for IERC20;

    struct Member {
        bool eligible;
        uint256 portionsClaimed;
    }

    IERC20 public token; // Token address

    uint256 public noOfPortions; // Number of vested portions
    uint256 public firstUnlock; // Unlock timestamp of first vested portion unlock
    uint256 public interval; // Time interval between portions
    uint256 public noOfMembers; // Number of members - accounts which can withdraw vested tokens
    uint256 public depositedTokens; // Total number of tokens to be distributed to users
    uint256 public portion; // Amount of tokens in a single portion

    mapping(address => Member) public members;

    event TokensDeposited(uint256 amount);
    event MemberAdded(address member);
    event SettingsUpdated(uint256 noOfPortions, uint256 interval, uint256 firstUnlock);
    event PortionUpdated(uint256 portion);
    event TokensClaimed(uint256 amount, uint256 numberOfPortions);

    modifier beforeFirstUnlock() {
        if (block.timestamp >= firstUnlock) {
            revert TimeLockClosed();
        }
        _;
    }

    function initialize(
        address _owner,
        address _token,
        uint256 _noOfPortions,
        uint256 _interval,
        uint256 _firstUnlock
    ) external initializer {
        if (
            _token == address(0) ||
            _noOfPortions == 0 ||
            _interval == 0 ||
            _firstUnlock >= block.timestamp - 900 ||
            _firstUnlock == 0
           ) {
            revert InvalidSettings();
        }

        token = IERC20(_token);
        noOfPortions = _noOfPortions;
        interval = _interval;
        firstUnlock = _firstUnlock;

        _transferOwnership(_owner);
    }

    function addMembers(address[] calldata newMembers) external onlyOwner beforeFirstUnlock {
        uint256 _noOfMembers = noOfMembers;
        for (uint i; i < newMembers.length; i++) {
            address member = newMembers[i];
            if (!members[member].eligible && member != address(0)) {
                members[member] = Member({eligible: true, portionsClaimed: 0});
                unchecked {
                    ++_noOfMembers;
                }
            }
            emit MemberAdded(member);
        }

        noOfMembers = _noOfMembers;

        updatePortion();
    }

    function depositTokens(uint256 amount) external onlyOwner beforeFirstUnlock {
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this));
        depositedTokens = received;
        emit TokensDeposited(received);
    }

    function updateSettings(
        uint256 _noOfPortions, 
        uint256 _interval, 
        uint256 _firstUnlock
    ) external onlyOwner beforeFirstUnlock {
        if (
            _noOfPortions == 0 ||
            _interval == 0 ||
            _firstUnlock >= block.timestamp - 900 ||
            _firstUnlock == 0
           ) {
            revert InvalidSettings();
        }

        noOfPortions = _noOfPortions;
        interval = _interval;
        firstUnlock = _firstUnlock;

        updatePortion();

        emit SettingsUpdated(_noOfPortions, _interval, _firstUnlock);
    }

    function withdraw() external {
        Member memory member = members[msg.sender];
        if (!member.eligible) {
            revert InvalidCaller();
        }
        uint256 totalAmount;
        uint256 portionsClaimed = member.portionsClaimed;
        uint256 portionsLeft = noOfPortions - portionsClaimed;
        uint256 portionTimestamp = firstUnlock + interval * portionsClaimed;
        uint256 singlePortionAmount = portion;
        for (uint i; i < portionsLeft; i++) {
            if (block.timestamp >= portionTimestamp) {
                unchecked {
                    totalAmount += singlePortionAmount;
                    portionTimestamp += interval;
                    portionsClaimed++;
                }
            } else break;
        }
        if (member.portionsClaimed < portionsClaimed) {
            unchecked {
                members[msg.sender].portionsClaimed = portionsClaimed;
                emit TokensClaimed(totalAmount, portionsClaimed - member.portionsClaimed);
            }
        }
    }

    function portionsUnlocked() external view returns (uint256) {
        uint256 counter;
        uint256 portionTimestamp = firstUnlock;
        for (uint i; i < noOfPortions; i++) {
            if (block.timestamp >= portionTimestamp) {
                unchecked {
                    counter++;
                    portionTimestamp += interval;
                }
            } else break;
        }
        return counter;
    }

    function portionsAvailable(address account) external view returns (uint256) {
        Member memory member = members[account];
        if (!member.eligible) {
            return 0;
        }
        uint256 portionsClaimed = member.portionsClaimed;
        uint256 portionsLeft = noOfPortions - portionsClaimed;
        uint256 portionTimestamp = firstUnlock + interval * portionsClaimed;
        uint256 counter;
        for (uint i; i < portionsLeft; i++) {
            if (block.timestamp >= portionTimestamp) {
                unchecked {
                    portionTimestamp += interval;
                    counter++;
                }
            } else break;
        }
        return counter;
    }

    function updatePortion() private {
        portion = depositedTokens / (noOfPortions * noOfMembers);
        emit PortionUpdated(portion);
    }
}
