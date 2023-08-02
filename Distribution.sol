// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
import "./IAllocationStaking.sol";

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}

contract Distribution {

    using SafeERC20 for IERC20Extented;

    struct UserTokens {
        uint256 amount;
        address userWallet;
    }

    struct Participation {
        uint256 userTokens;
        bool[] isPortionWithdrawn;
    }

    address public admin;
    bool public tokensDeposited;
    bool public isUserDataSeted;
    IERC20Extented public saleToken = IERC20Extented(0x0bD1d1163757eaC8ec64fd19D2357BD2dEA2aB78);
    uint256 public saleAmount;
    mapping(address => Participation) public userToParticipation;
    uint256[] public vestingPortionsUnlockTime;
    uint256[] public vestingPercentPerPortion;

    modifier onlyAdmin() {
        require(
            msg.sender == admin ,
            "Only admin can call this function."
        );
        _;
    }

    constructor(
        address _admin,
        uint256 _saleAmount)  {
            require(_admin != address(0));
            require(_saleAmount != 0);
            admin = _admin;
            saleAmount = _saleAmount;
    }

    function setVestingParams(
        uint256[] memory _unlockingTimes,
        uint256[] memory _percents
    ) external onlyAdmin {
        require(
            vestingPercentPerPortion.length == 0 &&
            vestingPortionsUnlockTime.length == 0
        );
        require(_unlockingTimes.length == _percents.length);

        uint256 sum;

        for (uint256 i = 0; i < _unlockingTimes.length; i++) {
            vestingPortionsUnlockTime.push(_unlockingTimes[i]);
            vestingPercentPerPortion.push(_percents[i]);
            sum += _percents[i];
        }

        require(sum == 100, "Percent distribution issue.");
    }

    function depositTokens() external {
        require(
            !tokensDeposited, "Deposit only once"
        );
        tokensDeposited = true;
        saleToken.safeTransferFrom(
            msg.sender,
            address(this),
            saleAmount
        );
    }

    function withdrawTokens(uint256 portionId) external {
        require(portionId < vestingPercentPerPortion.length);

        Participation storage p = userToParticipation[msg.sender];


        if (
            !p.isPortionWithdrawn[portionId] &&
            vestingPortionsUnlockTime[portionId] <= block.timestamp
        ) {
            p.isPortionWithdrawn[portionId] = true;
            uint256 amountWithdrawing = calculateAmountWithdrawing(msg.sender, vestingPercentPerPortion[portionId]);

            if(amountWithdrawing > 0) {
                saleToken.safeTransfer(msg.sender, amountWithdrawing);
            }
        } else {
            revert("Tokens withdrawn or portion not unlocked.");
        }
    }


    function withdrawMultiplePortions(uint256 [] calldata portionIds) external {
        uint256 totalToWithdraw = 0;

        Participation storage p = userToParticipation[msg.sender];


        for(uint i=0; i < portionIds.length; i++) {
            uint256 portionId = portionIds[i];
            require(portionId < vestingPercentPerPortion.length);

            if (
                !p.isPortionWithdrawn[portionId] &&
                vestingPortionsUnlockTime[portionId] <= block.timestamp
            ) {
                p.isPortionWithdrawn[portionId] = true;
                uint256 amountWithdrawing = calculateAmountWithdrawing(msg.sender, vestingPercentPerPortion[portionId]);
                totalToWithdraw = totalToWithdraw + amountWithdrawing;
            }
        }

        if(totalToWithdraw > 0) {
            saleToken.safeTransfer(msg.sender, totalToWithdraw);
        }
    }

    function getClaimedInfo(address userAddress)
    external 
    view 
    returns ( bool[] memory ){
        return (userToParticipation[userAddress].isPortionWithdrawn);
    }

    function getVestingInfo()
        external
        view
        returns (uint256[] memory, uint256[] memory)
    {
        return (vestingPortionsUnlockTime, vestingPercentPerPortion);
    }

    function calculateAmountWithdrawing(address userAddress, uint256 tokenPercent) internal view returns (
            uint256
        ) {
        
        Participation memory p = userToParticipation[userAddress];

        uint256 tokensForUser = p.userTokens * tokenPercent / 100 ;

        return (tokensForUser);
    }

    function calculateAmountWithdrawingPortionPub(address userAddress, uint256 tokenPercent) public view returns (
            uint256
        ) {

        uint256 tokensForUser = calculateAmountWithdrawing(userAddress, tokenPercent);

        return (tokensForUser);
    }


    function extrimalWithdraw( address tokenAddress, uint256 amount ) public onlyAdmin {
        IERC20Extented token = IERC20Extented(tokenAddress);
        token.safeTransfer(admin, amount);
    }


    function setUserDeposit(UserTokens[] calldata usersStake) public onlyAdmin {
        require(isUserDataSeted == false, "User data already seted");
        for (uint256 i = 0; i < usersStake.length; i++){
            bool[] memory _isPortionWithdrawn = new bool[](
                vestingPortionsUnlockTime.length
            );
            UserTokens memory stakeInfo = usersStake[i];
            Participation memory p = Participation({
                userTokens: stakeInfo.amount,
                isPortionWithdrawn: _isPortionWithdrawn
            });
            userToParticipation[stakeInfo.userWallet] = p;
        }
        isUserDataSeted = true;
    }
}
