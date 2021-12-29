// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ISalesFactory.sol";
import "./IAllocationStaking.sol";

contract PeakDefiSale {
    using ECDSA for bytes32;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Pointer to Allocation staking contract, where burnPeakFromUser will be called.
    IAllocationStaking public allocationStakingContract;
    // Pointer to sales factory contract
    ISalesFactory public factory;
    
    struct Sale {
        // Token being sold
        IERC20 token;
        // Is sale created
        bool isCreated;
        // Are earnings withdrawn
        bool earningsWithdrawn;
        // Is leftover withdrawn
        bool leftoverWithdrawn;
        // Have tokens been deposited
        bool tokensDeposited;
        // Address of sale owner
        address saleOwner;
        // Price of the token quoted in BUSD
        uint256 tokenPriceInBUSD;
        // Amount of tokens to sell
        uint256 amountOfTokensToSell;
        // Total tokens being sold
        uint256 totalTokensSold;
        // Total AVAX Raised
        uint256 totalBUSDRaised;
        // Sale end time
        uint256 saleEnd;
        // Sale start time
        uint256 saleStart;
        // When tokens can be withdrawn
        uint256 tokensUnlockTime;
    }

    // Participation structure
    struct Participation {
        uint256 amountPaid;
        uint256 timeParticipated;
        uint256 tierId;
        bool[] isPortionWithdrawn;
    }

    // Tier structure
    struct Tier {
        uint256 participants;
        uint256 tierWeight; 
        uint256 BUSDDeposited;
        uint256 minToStake;
        uint256 maxToStake;
    }

    // Whitelist User structure
    struct WhitelistUser {
        address userAddress;
        uint256 userTierId;
    }

    // Registration structure
    struct Registration {
        uint256 registrationTimeStarts;
        uint256 registrationTimeEnds;
        uint256 numberOfRegistrants;
    }

    // Sale
    Sale public sale;
    // Registration
    Registration public registration;
    //Admin address
    address public admin;
    // BUSD Token
    IERC20 public BUSDToken = IERC20(0x8336B8B45d6edae6354d0985089A6dF8A7ada97f);
    // Number of participats per round
    uint256 public numberOfParticipants;
    // Mapping user to his participation
    mapping(address => Participation) public userToParticipation;
    // mapping if user is participated or not
    mapping(address => bool) public isParticipated;
    // mapping if user is whitelisted
    mapping(address => WhitelistUser) public Whitelist;
    // Times when portions are getting unlocked
    uint256[] public vestingPortionsUnlockTime;
    // Percent of the participation user can withdraw
    uint256[] public vestingPercentPerPortion;
    //Precision for percent for portion vesting
    uint256 public portionVestingPrecision;
    // Added configurable round ID for staking round
    uint256 public stakingRoundId;
    // Max vesting time shift
    uint256 public maxVestingTimeShift;
    // Accounting total BUST collected, after sale admin can withdraw this
    uint256 public registrationFees;
    // Tiers for Sale
    Tier[] public tierIdToTier;
    // total tier weight
    uint256 public totalTierWeight;
    // minimum token to stake for Sale
    uint256 minimumTokensToStake = 100;

    // Restricting calls only to sale owner
    modifier onlySaleOwner() {
        require(msg.sender == sale.saleOwner, "OnlySaleOwner:: Restricted");
        _;
    }

    // Only admin can call this function.
    modifier onlyAdmin() {
        require(
            msg.sender == admin ,
            "Only admin can call this function."
        );
        _;
    }

    // Check wallet allowance for contract
    modifier _hasAllowance(IERC20 token, address allower, uint256 amount) {
        // Make sure the allower has provided the right allowance.
        uint256 ourAllowance = token.allowance(allower, address(this));
        require(amount <= ourAllowance, "Make sure to add enough allowance");
        _;
    }

    // EVENTS

    event TokensSold(address user, uint256 amount);
    event TokenPriceSet(uint256 newPrice);
    event TokensWithdrawn(address user, uint256 amount);
    event SaleCreated(
        address saleOwner,
        uint256 tokenPriceInBUSD,
        uint256 amountOfTokensToSell,
        uint256 saleEnd,
        uint256 tokensUnlockTime
    );
    event RegistrationTimeSet(
        uint256 registrationTimeStarts,
        uint256 registrationTimeEnds
    );

    // Constructor, always initialized through SalesFactory
    constructor(
        address _admin, 
        address _allocationStaking)  {
            require(_admin != address(0));
            require(_allocationStaking != address(0));
            admin = _admin;
            factory = ISalesFactory(msg.sender);
            allocationStakingContract = IAllocationStaking(_allocationStaking);
    }

    /// @notice         Function to set vesting params
    function setVestingParams(
        uint256[] memory _unlockingTimes,
        uint256[] memory _percents,
        uint256 _maxVestingTimeShift
    ) external onlyAdmin {
        require(
            vestingPercentPerPortion.length == 0 &&
            vestingPortionsUnlockTime.length == 0
        );
        require(_unlockingTimes.length == _percents.length);
        require(portionVestingPrecision > 0, "Safeguard for making sure setSaleParams get first called.");
        require(_maxVestingTimeShift <= 30 days, "Maximal shift is 30 days.");

        // Set max vesting time shift
        maxVestingTimeShift = _maxVestingTimeShift;

        uint256 sum;

        for (uint256 i = 0; i < _unlockingTimes.length; i++) {
            vestingPortionsUnlockTime.push(_unlockingTimes[i]);
            vestingPercentPerPortion.push(_percents[i]);
            sum += _percents[i];
        }

        require(sum == portionVestingPrecision, "Percent distribution issue.");
    }

    function shiftVestingUnlockingTimes(uint256 timeToShift)
        external
        onlyAdmin
    {
        require(
            timeToShift > 0 && timeToShift < maxVestingTimeShift,
            "Shift must be nonzero and smaller than maxVestingTimeShift."
        );

        // Time can be shifted only once.
        maxVestingTimeShift = 0;

        for (uint256 i = 0; i < vestingPortionsUnlockTime.length; i++) {
            vestingPortionsUnlockTime[i] = vestingPortionsUnlockTime[i].add(
                timeToShift
            );
        }
    }

    /// @notice     Admin function to set sale parameters
    function setSaleParams(
        address _token,
        address _saleOwner,
        uint256 _tokenPriceInBUSD,
        uint256 _amountOfTokensToSell,
        uint256 _saleEnd,
        uint256 _tokensUnlockTime,
        uint256 _portionVestingPrecision,
        uint256 _stakingRoundId
    ) external onlyAdmin {
        require(!sale.isCreated, "setSaleParams: Sale is already created.");
        require(
            _saleOwner != address(0),
            "setSaleParams: Sale owner address can not be 0."
        );
        require(
            _tokenPriceInBUSD != 0 &&
                _amountOfTokensToSell != 0 &&
                _saleEnd > block.timestamp &&
                _tokensUnlockTime > block.timestamp,
            "setSaleParams: Bad input"
        );
        require(_portionVestingPrecision >= 100, "Should be at least 100");
        // TODO: validate
        require(_stakingRoundId > 0, "Staking round ID can not be 0.");
        // Set params
        sale.token = IERC20(_token);
        sale.isCreated = true;
        sale.saleOwner = _saleOwner;
        sale.tokenPriceInBUSD = _tokenPriceInBUSD;
        sale.amountOfTokensToSell = _amountOfTokensToSell;
        sale.saleEnd = _saleEnd;
        sale.tokensUnlockTime = _tokensUnlockTime;
        portionVestingPrecision = _portionVestingPrecision;
        stakingRoundId = _stakingRoundId;
        emit SaleCreated(
            sale.saleOwner,
            sale.tokenPriceInBUSD,
            sale.amountOfTokensToSell,
            sale.saleEnd,
            sale.tokensUnlockTime
        );
    }

    /// @notice     Function to set registration period parameters
    function setRegistrationTime(
        uint256 _registrationTimeStarts,
        uint256 _registrationTimeEnds
    ) external onlyAdmin {
        require(sale.isCreated);
        require(registration.registrationTimeStarts == 0);
        require(
            _registrationTimeStarts >= block.timestamp &&
                _registrationTimeEnds > _registrationTimeStarts
        );
        require(_registrationTimeEnds < sale.saleEnd);


        registration.registrationTimeStarts = _registrationTimeStarts;
        registration.registrationTimeEnds = _registrationTimeEnds;

        emit RegistrationTimeSet(
            registration.registrationTimeStarts,
            registration.registrationTimeEnds
        );
    }

    // @notice     Function to retroactively set sale token address, can be called only once,
    //             after initial contract creation has passed. Added as an options for teams which
    //             are not having token at the moment of sale launch.
    function setSaleToken(
        address saleToken
    )
    external
    onlyAdmin
    {
        require(address(sale.token) == address(0));
        sale.token = IERC20(saleToken);
    }

    /// @notice     Registration for sale.
    function registerForSale() public {

        uint256 stakeAmount = allocationStakingContract.deposited(stakingRoundId, msg.sender);

        require(stakeAmount > minimumTokensToStake, "Need to stake tokens");
        require(
            block.timestamp >= registration.registrationTimeStarts &&
                block.timestamp <= registration.registrationTimeEnds,
            "Registration gate is closed."
        );
        for (uint256 i = 0; i < tierIdToTier.length; i++) {
            Tier memory t = tierIdToTier[i];
            if( t.minToStake <= stakeAmount && t.maxToStake < stakeAmount){
                WhitelistUser memory u = WhitelistUser({
                userAddress: msg.sender, 
                userTierId: i
                });
                // Set whitelist user
                Whitelist[msg.sender] = u;
                // Increment number of registered users
                registration.numberOfRegistrants++;
                break;
            }
        }
    }
    
    /// @notice     Update token price.
    function updateTokenPriceInBUSD(uint256 price) external onlyAdmin {
        require(price > 0, "Price can not be 0.");
        sale.tokenPriceInBUSD = price;
        emit TokenPriceSet(price);
    }

    /// @notice     Set user for whitelist
    function setWhitelistUsers(address [] calldata users, uint256 tierId) public payable {

        require( 
                tierId > 0,
                "Tier id can`t be lower than 0"
            );

         for (uint256 i = 0; i < users.length; i++) {

            WhitelistUser memory u = WhitelistUser({
            userAddress: users[i], 
            userTierId: tierId
            });
            Whitelist[users[i]] = u;
        }
        
    }

    /// @notice     Add new tiers for sale
    function addTiers(uint256 [] calldata tierWeights, uint256 [] calldata tiersStaking)  public {   
        
        require(tierWeights.length > 0, "Need to be more than 1 tier");
        require(tierWeights.length == tiersStaking.length, "Staking and weights must be th same length");


        uint256 endPrevBlockStakePoints = tierIdToTier.length == 0 ? minimumTokensToStake : tierIdToTier[tierIdToTier.length - 1].minToStake;

        for (uint256 i = 0; i < tierWeights.length; i++) {
            require( 
                tierWeights[i] > 0,
                "Tier weight must be greater then 0"
            );

            require( tiersStaking[i] > endPrevBlockStakePoints, "Your next block can`t have lees LP token to stake then last one");

            totalTierWeight = totalTierWeight.add(tierWeights[i]);

            Tier memory t = Tier({
                participants: 0,
                tierWeight: tierWeights[i],
                BUSDDeposited: 0,
                minToStake: endPrevBlockStakePoints,
                maxToStake: tiersStaking[i]
            });
            tierIdToTier.push(t);

            endPrevBlockStakePoints = tiersStaking[i];
        }

     
    }


    // Function for owner to deposit tokens, can be called only once.
    function depositTokens() external onlySaleOwner _hasAllowance(sale.token, msg.sender, sale.amountOfTokensToSell) {
        require(
            !sale.tokensDeposited, "Deposit can be done only once"
        );

        sale.tokensDeposited = true;

        sale.token.safeTransferFrom(
            msg.sender,
            address(this),
            sale.amountOfTokensToSell
        );
    }


    // Function to participate in the sales
    function participate(uint256 amount) 
    external 
    payable 
    // _hasAllowance(BUSDToken, msg.sender, amount)
    {
        // Check sale created
        require(sale.isCreated, "Wait for sale create");

        // Check sale active
        require( block.timestamp >= sale.saleStart && block.timestamp <= sale.saleEnd , "Sale is not active now");

        // Check user haven't participated before
        require(!isParticipated[msg.sender], "User can participate only once.");

        // Disallow contract calls.
        require(msg.sender == tx.origin, "Only direct contract calls.");

        // Compute the amount of tokens user is buying
        uint256 amountOfTokensDeposited = (amount);

        // Must buy more than 0 tokens
        require(amountOfTokensDeposited > 0, "Can't buy 0 tokens");


        require( Whitelist[msg.sender].userTierId != 0, "User must be in white list" );

        uint256 _tierId = Whitelist[msg.sender].userTierId;
        // Increase amount of BUSD raised
        sale.totalBUSDRaised = sale.totalBUSDRaised.add(amount);

        bool[] memory _isPortionWithdrawn = new bool[](
            vestingPortionsUnlockTime.length
        );

        // Create participation object
        Participation memory p = Participation({
            amountPaid: amount,
            timeParticipated: block.timestamp,
            tierId: _tierId,
            isPortionWithdrawn: _isPortionWithdrawn
        });

        Tier storage t = tierIdToTier[_tierId];

        t.participants = t.participants.add(1);
        t.BUSDDeposited = t.BUSDDeposited.add(amount);
        // Add participation for user.
        userToParticipation[msg.sender] = p;
        // Mark user is participated
        isParticipated[msg.sender] = true;
        // Increment number of participants in the Sale.
        numberOfParticipants++;

        BUSDToken.transferFrom(msg.sender, address(this), amountOfTokensDeposited);
    }

    /// Users can claim their participation
    function withdrawTokens(uint256 portionId) external {
        require(
            block.timestamp >= sale.tokensUnlockTime,
            "Tokens can not be withdrawn yet."
        );
        require(portionId < vestingPercentPerPortion.length);

        Participation storage p = userToParticipation[msg.sender];

        if (
            !p.isPortionWithdrawn[portionId] &&
            vestingPortionsUnlockTime[portionId] <= block.timestamp
        ) {
            p.isPortionWithdrawn[portionId] = true;
            uint256 amountWithdrawing = calculateAmountWithdrawingPortion(msg.sender, vestingPercentPerPortion[portionId]);

            // Withdraw percent which is unlocked at that portion
            if(amountWithdrawing > 0) {
                sale.token.safeTransfer(msg.sender, amountWithdrawing);
                emit TokensWithdrawn(msg.sender, amountWithdrawing);
            }
        } else {
            revert("Tokens already withdrawn or portion not unlocked yet.");
        }
    }

    

    // Expose function where user can withdraw multiple unlocked portions at once.
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
                uint256 amountWithdrawing = calculateAmountWithdrawingPortion(msg.sender, vestingPercentPerPortion[portionId]);
                // Withdraw percent which is unlocked at that portion
                totalToWithdraw = totalToWithdraw.add(amountWithdrawing);
            }
        }

        if(totalToWithdraw > 0) {
            sale.token.safeTransfer(msg.sender, totalToWithdraw);
            emit TokensWithdrawn(msg.sender, totalToWithdraw);
        }
    }

    // Internal function to handle safe transfer
    function safeTransferPEAK(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success);
    }

    /// Function to withdraw all the earnings and the leftover of the sale contract.
    function withdrawEarningsAndLeftover() external onlySaleOwner {
        withdrawEarningsInternal();
        withdrawLeftoverInternal();
    }

    // Function to withdraw only earnings
    function withdrawEarnings() external onlySaleOwner {
        withdrawEarningsInternal();
    }

    // Function to withdraw only leftover
    function withdrawLeftover() external onlySaleOwner {
        withdrawLeftoverInternal();
    }


    // function to withdraw earnings
    function withdrawEarningsInternal() internal  {
        // Make sure sale ended
        require(block.timestamp >= sale.saleEnd);

        // Make sure owner can't withdraw twice
        require(!sale.earningsWithdrawn);
        sale.earningsWithdrawn = true;
        // Earnings amount of the owner in PEAK
        uint256 totalProfit = sale.totalBUSDRaised;

        safeTransferPEAK(msg.sender, totalProfit);
    }

    // Function to withdraw leftover
    function withdrawLeftoverInternal() internal {
        require(block.timestamp >= sale.saleEnd);
        require(!sale.leftoverWithdrawn);
        sale.leftoverWithdrawn = true;
        uint256 leftover = sale.amountOfTokensToSell.sub(sale.totalTokensSold);
        if (leftover > 0) {
            sale.token.safeTransfer(msg.sender, leftover);
        }
    }
    function withdrawRegistrationFees() external onlyAdmin {
        require(block.timestamp >= sale.saleEnd, "Require that sale has ended.");
        require(registrationFees > 0, "No earnings from registration fees.");
        safeTransferPEAK(msg.sender, registrationFees);
        registrationFees = 0;
    }
    function withdrawUnusedFunds() external onlyAdmin {
        uint256 balancePEAK = address(this).balance;

        uint256 totalReservedForRaise = sale.earningsWithdrawn ? 0 : sale.totalBUSDRaised;

        safeTransferPEAK(
            msg.sender,
            balancePEAK.sub(totalReservedForRaise.add(registrationFees))
        );
    }

    function getParticipation(address _user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool[] memory
        )
    {
        Participation memory p = userToParticipation[_user];
        return (
            p.amountPaid,
            p.timeParticipated,
            p.tierId,
            p.isPortionWithdrawn
        );
    }

    function getVestingInfo()
        external
        view
        returns (uint256[] memory, uint256[] memory)
    {
        return (vestingPortionsUnlockTime, vestingPercentPerPortion);
    }

    function calculateAmountWithdrawingPortion(address userAddress, uint256 tokenPercent) internal view returns (
            uint256
        ) {
        
        Participation memory p = userToParticipation[userAddress];

        Tier memory t = tierIdToTier[uint(p.tierId)];

        uint256 tokensPerTier = t.tierWeight.mul(sale.amountOfTokensToSell).div(totalTierWeight);

        uint256 tokensForUser = tokensPerTier.mul(tokenPercent).div(t.participants).div(100);

        return (tokensForUser);
    }

    function calculateAmountWithdrawingPortionPub(address userAddress, uint256 tokenPercent) public view returns (
            uint256
        ) {
        
        Participation memory p = userToParticipation[userAddress];

        Tier memory t = tierIdToTier[uint(p.tierId)];

        uint256 tokensPerTier = t.tierWeight.mul(sale.amountOfTokensToSell).div(totalTierWeight);

        uint256 tokensForUser = tokensPerTier.mul(tokenPercent).div(t.participants).div(100);

        return (tokensForUser);
    }
}