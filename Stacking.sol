// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AllocationStaking {

    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 stakingStart;
    }

    uint256 internal secondsPerDay = 86400;
    uint256 public stakingPercent = 20;
    uint256 public secondsPreYear = 31556926;

    IERC20 stakingToken;


    address admin;
    // The total amount of ERC20 that's paid out as reward.
    uint256 public paidOut;
    // Total rewards added to farm
    uint256 public totalRewards;
    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;

    //Total token deposited
    uint256 public totalDeposits;


    modifier onlyOwner {
        require( admin == msg.sender , "Sale not created through factory.");
        _;
    }

    constructor ()  {
        admin = msg.sender;
     }

    function setStakingToken(
        IERC20 _erc20
    )
    public onlyOwner
    {
        stakingToken = _erc20;
    }

    function fund(uint256 _amount) public onlyOwner {
        stakingToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        totalRewards = totalRewards+_amount;
    }

    function withdraw(uint256 _amount) public{
        UserInfo storage user = userInfo[msg.sender];
        require( user.amount >= _amount, "Not enough balance" );


        uint256 withdrawFee = getFeeInternal(_amount, user.stakingStart);
        uint256 tokenToWithdraw = _amount-withdrawFee;       

        harvest();
        totalRewards = totalRewards+withdrawFee;

        user.stakingStart = block.timestamp;
        user.amount = user.amount-_amount;

        totalDeposits = totalDeposits-_amount;
        stakingToken.safeTransfer(address(msg.sender), tokenToWithdraw);
    }

    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];

        // Harvest user pending tokens
        if ( user.amount != 0 ){
            harvest();
        }

        stakingToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        totalDeposits = totalDeposits+_amount;

        user.amount = user.amount+_amount;
        user.stakingStart = block.timestamp;
    }

    function deposited(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        return user.amount;
    }

    function pending() public view returns(uint256){
       UserInfo memory user = userInfo[msg.sender];
       uint256 pendingTokens = pendingAmountInternal(user.stakingStart, user.amount);
       return(pendingTokens);
    }

    function harvest() internal{
        UserInfo storage user = userInfo[msg.sender];

        uint256 userPendingEarns = pending();

        require( userPendingEarns <= totalRewards, "Not enough token" );

        stakingToken.safeTransfer(address(msg.sender), userPendingEarns);
        user.stakingStart = block.timestamp;
        totalRewards = totalRewards - userPendingEarns;
        paidOut = paidOut + userPendingEarns;
    }
   

    function getWithdrawFee(address userAddress, uint256 amountToWithdraw) external view returns (uint256) {
        UserInfo storage user = userInfo[userAddress];

        return getFeeInternal(amountToWithdraw, user.stakingStart);
    }

    function getFeeInternal( uint256 amount, uint256 stakingStart )  public view returns(uint256){
        
        uint256 withdrawFeePercent = getUnstakePercent(block.timestamp-stakingStart);
        
        return(amount*withdrawFeePercent/100);
    }


    function pendingAmountInternal(uint256 _stakingStart, uint256 _amount) internal view returns(uint256){
        uint256 currenntTimestamp = block.timestamp;
        uint256 stakingDuration = currenntTimestamp-_stakingStart;

        uint256 pendingTokens = _amount*stakingDuration*stakingPercent/100/secondsPreYear;

        return (pendingTokens);
    }

    function getUnstakePercent(uint256 stakingTime) internal view returns (uint256){
        uint256 unstakePercent = 0;
        if ( stakingTime < secondsPerDay*14 ){
            unstakePercent = 30;
        } else if ( stakingTime < secondsPerDay*28 ){
            unstakePercent = 20;
        } else if ( stakingTime < secondsPerDay*42 ){
            unstakePercent = 10;
        } else if ( stakingTime < secondsPerDay*56 ){
            unstakePercent = 5;
        }
        return (unstakePercent);
    }

}