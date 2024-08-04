// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DZapStaking is
    ERC721Holder,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    /// @notice Structure which contains staked NFT information.
    struct StakedNft {
        uint256 stakedAt;
        uint256 unstakedAt;
        uint256 unbondingPeriodEndsAt;
        uint256 delayPeriodEndsAt;
        address owner;
        bool isUnstaked;
        bool isWithdrawn;
    }

    /// @notice ERC20 Reward token for staking.
    IERC20 public dzapReward;
    /// @notice ERC721 NFT collection to stake tokenId from.
    IERC721 public dZapNft;

    /// @notice Reward per block for staking.
    uint256 public rewardPerBlock;

    /// @notice Unbonding period after tokenId is unstaked.
    uint256 public constant unbondingPeriod = 20;

    /// @notice Delay period after NFT is withdrawn to claim rewards.
    uint256 public constant delayPeriod = 30;

    /// @notice Mapping from 'tokenId' to 'StakedNft'.
    mapping(uint256 => StakedNft) public tokenIdToStakedNft;

    /// @notice Mapping from 'user' to their unstaked 'tokenIds'.
    mapping(address => uint256[]) public userToUnstakedTokenIds;


    // ::::::::::::::::::::::::::::: events :::::::::::::::::::::::::::::

    /// @notice Emitted when 'user' stakes 'tokenIds'
    event Staked(address indexed user, uint256[] indexed tokenIds);

    /// @notice Emitted when 'user' unstakes 'tokenIds'
    event Unstaked(address indexed user, uint256[] indexed tokenIds);

    /// @notice Emitted when 'owner' updates 'rewardPerBlock'
    event RewardUpdated(uint256 indexed oldRewardPerBlock, uint256 indexed newRewardPerBlock);

    /// @notice Emitted when 'user' withdraws their 'tokenIds'.
    event NftWithdrawn(address indexed user, uint256[] indexed tokenIds);

    /// @notice Emitted when 'user' claims their 'rewards'.
    event RewardsClaimed(address indexed user, uint256 indexed rewards);

    /// @notice Initializes the contract by setting addresses for initial owner, reward token and NFT collection.
    /// @dev The function reverts if '_dzapReward' and '_dzapNFT' are not contract addresses. This function can be called only once.
    /// @param _initialOwner Address of the initial owner of this contract.
    /// @param _dzapReward Address of the ERC20 reward token.
    /// @param _dzapNFT Address of the ERC721 NFT collection.
    function initialize(address _initialOwner, address _dzapReward, address _dzapNFT, uint256 _rewardPerBlock) public initializer {
        require(checkIfContract(_dzapReward) && checkIfContract(_dzapNFT), "Invalid contract addresses!");
        require(_rewardPerBlock > 0, "Reward per block must be greater than zero.");

        __Ownable_init(_initialOwner);

        dzapReward = IERC20(_dzapReward);
        dZapNft = IERC721(_dzapNFT);
        rewardPerBlock = _rewardPerBlock;
    }

    /// @notice Stakes NFTs by transferring them from 'msg.sender' to the contract.
    /// @dev The contract should be approved as 'operator' for 'tokenIds'. Reverts if zero 'tokenIds' are passed as argument.
    /// @param _tokenIds Array of tokenIds to stake.
    function stake(uint256[] calldata _tokenIds) external whenNotPaused nonReentrant {
        uint256 numTokenIds = _tokenIds.length;
        require(numTokenIds > 0, "You must stake at least one NFT.");

        uint256 i;
        do {
            uint256 tokenId = _tokenIds[i];
            dZapNft.safeTransferFrom(msg.sender, address(this), tokenId);
            tokenIdToStakedNft[tokenId] = StakedNft(block.number, 0, 0, 0, msg.sender, false, false);

            unchecked {
                ++i;
            }
        } while (i < numTokenIds);

        emit Staked(msg.sender, _tokenIds);
    }

    /// @notice Function to unstake NFTs.
    /// @dev The NFTs are marked as unstaked and 'unbondingPeriod' starts.
    /// @dev Reverts if zero 'tokenIds' are passed as argument or 'tokenId' is not staked.
    /// @param _tokenIds Array of 'tokenIds' to unstake.
    function unstake(uint256[] calldata _tokenIds) external nonReentrant {
        uint256 numTokenIds = _tokenIds.length;
        require(numTokenIds > 0, "You must unstake at least one NFT.");

        uint256 i;
        do {
            uint256 tokenId = _tokenIds[i];
            StakedNft storage stakedNft = tokenIdToStakedNft[tokenId];

            require(stakedNft.owner == msg.sender, "Only NFT owner can unstake.");
            require(!stakedNft.isUnstaked, "NFT is not staked.");
            stakedNft.unstakedAt = block.number;
            stakedNft.isUnstaked = true;
            stakedNft.unbondingPeriodEndsAt = block.number + unbondingPeriod;
            userToUnstakedTokenIds[msg.sender].push(tokenId);

            unchecked {
                ++i;
            }
        } while (i < numTokenIds);

        emit Unstaked(msg.sender, _tokenIds);
    }

    /// @notice Function to withdraw unstaked NFTs.
    /// @dev The NFTs are transferred back to the owner after 'unbondingPeriod' gets over.
    /// @dev Reverts if no 'tokenId' is unstaked or if 'unbondingPeriod' has not finished.
    function withdraw() external nonReentrant {
        uint256[] memory unstakedTokenIds = userToUnstakedTokenIds[msg.sender];
        require(unstakedTokenIds.length > 0, "You dont have any unstaked NFT to withdraw.");

        uint256 i;
        do {
            require(
                block.number > tokenIdToStakedNft[unstakedTokenIds[i]].unbondingPeriodEndsAt,
                "Unbonding period has not finished."
            );
            tokenIdToStakedNft[unstakedTokenIds[i]].isWithdrawn = true;
            tokenIdToStakedNft[unstakedTokenIds[i]].delayPeriodEndsAt = block.number + delayPeriod;
            dZapNft.safeTransferFrom(address(this), msg.sender, unstakedTokenIds[i]);
        
            unchecked {
                ++i;
            }
        } while (i < unstakedTokenIds.length);

        emit NftWithdrawn(msg.sender, unstakedTokenIds);
    }

    /// @notice Function to allow users to claim their rewards.
    /// @dev Calculates reward tokens for 'msg.sender' and transfers them.
    /// @dev Reverts if 'msg.sender' doesn't have any rewards to claim.
    function claimRewards() external nonReentrant {
        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, "You do not have any rewards to claim.");

        dzapReward.transfer(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @notice Function to calculate rewards.
    /// @dev Reverts if the '_user' doesn't have any unstaked NFTs.
    /// @dev Reverts if 'delayPeriod' has not finished or NFT is not withdrawn.
    /// @param _user Address of the user to calculate rewards.
    /// @return rewards Returns total rewards of '_user'.
    function calculateRewards(address _user) private returns (uint256 rewards) {
        require(_user != address(0), "Invalid address!");

        uint256 unstakedTokenIds = userToUnstakedTokenIds[_user].length;
        require(unstakedTokenIds > 0, "User doesnt have any unstaked NFT.");

        uint256 i;
        do {
            uint256 tokenId = userToUnstakedTokenIds[_user][i];
            StakedNft storage stakedNft = tokenIdToStakedNft[tokenId];

            require(stakedNft.isWithdrawn, "NFT is not withdrawn.");
            require(block.number > stakedNft.delayPeriodEndsAt, "Delay period has not finished.");

            uint256 timeElapsed = stakedNft.unbondingPeriodEndsAt - stakedNft.stakedAt;
            rewards += timeElapsed * rewardPerBlock;

            delete tokenIdToStakedNft[tokenId];

            unchecked {
                ++i;
            }
        } while (i < unstakedTokenIds);
    }

    /// @notice Function to update the 'rewardPerBlock'.
    /// @dev Reverts if 'msg.sender' is not 'owner'.
    /// @dev Reverts if zero is passed as argument.
    /// @param _rewardPerBlock New reward per block .
    function updateReward(uint256 _rewardPerBlock) external onlyOwner {
        require(_rewardPerBlock > 0, "Reward per block must be greater than zero.");
        uint256 oldRewardPerBlock = rewardPerBlock;
        rewardPerBlock = _rewardPerBlock;

        emit RewardUpdated(oldRewardPerBlock, rewardPerBlock);
    }

    /// @notice Checks if an address is a contract address.
    /// @param _addr Address to check.
    /// @return True if the address points to a contract else false.
    function checkIfContract(address _addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /// @notice Function to authorize an upgrade of the contract.
    /// @dev Reverts if 'msg.sender. is not 'owner'. Called by the function 'upgradeToAndCall'.
    /// @param _newImplementation Address of the new implementation for upgrade.
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
