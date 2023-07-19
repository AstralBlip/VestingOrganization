// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error ImplementationAlreadySet();
error ImplementationNotSet();
error CloneCreationFailed();
error NotCreatedThroughFactory();
error InvalidIndexRange();
error InvalidCaller();

interface IVestingOrganization {
    function initialize(address token) external;

    function addParticipants(
        address[] memory participants,
        uint256[] memory _portionAmounts,
        uint256[] memory _portionTimestamps
    ) external;

    function withdraw(address participant, uint256[] calldata portions) external returns (uint256);

    function removeParticipant(address participant) external;

    function depositTokens(uint256 amount) external;

    function token() external view returns (IERC20);
}

contract VestingOrganizationManager is Ownable {

    using SafeERC20 for IERC20;

    // Contains vesting contracts deployed by this factory
    mapping(address => bool) public deployedThroughFactory;
    // Organization to owner
    mapping(address => address) public organizationOwner;
    // Expose so query can be possible only by position as well
    address[] public deployments;
    // Vesting contract implementation
    address public implementation;

    // Events
    event Deployed(address addr);
    event ImplementationSet(address implementation);

    event ParticipantsAdded(address organization, address[] participants);
    event TokensDeposited(address organization, uint256 amount);
    event TokensWithdrawn(address organization, address participant, uint256 amount);

    modifier organizationChecks(address organization) {
        _organizationChecks(organization);
        _;
    }

    function _organizationChecks(address organization) private view {
        if (msg.sender != organizationOwner[organization]) {
            revert InvalidCaller();
        }
        if (!deployedThroughFactory[organization]) {
            revert NotCreatedThroughFactory();
        }
    }

    constructor(address owner) {
        transferOwnership(owner);
    }

    /**
     * @notice Function to set the latest implementation
     * @param _implementation is vesting contract implementation
     */
    function setImplementation(address _implementation) external onlyOwner {
        // Require that implementation is different from current one
        if (_implementation == implementation) {
            revert ImplementationAlreadySet();
        }
        // Set new implementation
        implementation = _implementation;
        // Emit relevant event
        emit ImplementationSet(implementation);
    }

    /**
     * @notice Function to deploy new vesting contract instance
     */
    function deploy(
        address owner,
        address token
    ) external onlyOwner {
        // Require that implementation is set
        if (implementation == address(0)) {
            revert ImplementationNotSet();
        }

        // Deploy clone
        address clone;
        // Inline assembly works only with local vars
        address imp = implementation;

        /// @solidity memory-safe-assembly
        assembly {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, imp)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, imp), 0x5af43d82803e903d91602b57fd5bf3))
            clone := create(0, 0x09, 0x37)
        }
        // Require that clone is created
        if (clone == address(0)) {
            revert CloneCreationFailed();
        }

        // Mark sale as created through official factory
        deployedThroughFactory[clone] = true;
        // Set ownership
        organizationOwner[clone] = owner;
        // Add sale to allSales
        deployments.push(clone);

        // Initialize instance
        IVestingOrganization(clone).initialize(
            token
        );

        // Emit relevant event
        emit Deployed(clone);
    }

    function addParticipantsToOrganization(
        address organization,
        address[] memory participants,
        uint256[] memory portionAmounts,
        uint256[] memory portionTimestamps
    ) external organizationChecks(organization) {
        IVestingOrganization(organization).addParticipants(
            participants,
            portionAmounts,
            portionTimestamps
        );
        emit ParticipantsAdded(organization, participants);
    }

    function depositTokensToOrganization(
        address organization,
        uint256 amount
    ) external organizationChecks(organization) {
        IERC20 token = IVestingOrganization(organization).token();
        token.safeTransferFrom(msg.sender, address(this), amount);
        token.approve(organization, amount);
        IVestingOrganization(organization).depositTokens(amount);
        emit TokensDeposited(organization, amount);
    }

    function withdrawTokensFromOrganization(
        address organization,
        address participant,
        uint256[] calldata portions
    ) external organizationChecks(organization) {
        uint256 total = IVestingOrganization(organization).withdraw(participant, portions);
        emit TokensWithdrawn(organization, participant, total);
    }

    /// @notice Function to return number of pools deployed
    function deploymentsCounter() external view returns (uint) {
        return deployments.length;
    }

    /// @notice Get most recently deployed sale
    function getLatestDeployment() external view returns (address) {
        if (deployments.length > 0) return deployments[deployments.length - 1];
        // Return zero address if no deployments were made
        return address(0);
    }

    /**
     * @notice Function to get all deployments between indexes
     * @param startIndex first margin
     * @param endIndex second margin
     */
    function getAllDeployments(uint startIndex, uint endIndex) external view returns (address[] memory) {
        // Require valid index input
        if (endIndex < startIndex || endIndex >= deployments.length) {
            revert InvalidIndexRange();
        }
        // Create new array
        address[] memory _deployments = new address[](endIndex - startIndex + 1);
        uint index = 0;
        // Fill the array with sale addresses
        for (uint i = startIndex; i <= endIndex; i++) {
            _deployments[index] = deployments[i];
            index++;
        }
        return _deployments;
    }
}
