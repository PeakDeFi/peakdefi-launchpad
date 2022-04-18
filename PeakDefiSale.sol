// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
import "./ISalesFactory.sol";
import "./IAllocationStaking.sol";

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}

contract PeakDefiSale {

    using SafeERC20 for IERC20Extented;

    IAllocationStaking public allocationStakingContract;
    ISalesFactory public factory;
    
    struct Sale {
        IERC20Extented token;
        bool isCreated;
        bool earningsWithdrawn;
        bool leftoverWithdrawn;
        address saleOwner;
        uint256 tokenPriceInBUST;
        uint256 amountOfTokensToSell;
        uint256 totalBUSDRaised;
        uint256 saleEnd;
        uint256 saleStart;
        uint256 tokensUnlockTime;
        uint256 minimumTokenDeposit;
    }
    struct Participation {
        uint256 amountPaid;
        uint256 timeParticipated;
        uint256 tierId;
        bool isTokenLeftWithdrawn;
        bool[] isPortionWithdrawn;
    }


    struct Tier {
        uint256 participants;
        uint256 tierWeight; 
        uint256 BUSTDeposited;
        uint256 minToStake;
        uint256 maxToStake;
    }

    struct WhitelistUser {
        address userAddress;
        uint256 userTierId;
    }

    struct Registration {
        uint256 registrationTimeStarts;
        uint256 registrationTimeEnds;
        uint256 numberOfRegistrants;
    }

    Sale public sale;
    Registration public registration;
    address public admin;
    bool tokensDeposited;
    IERC20Extented public BUSDToken = IERC20Extented(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    uint256 public numberOfParticipants;
    mapping(address => Participation) public userToParticipation;
    mapping(address => uint256) public addressToRoundRegisteredFor;
    mapping(address => bool) public isParticipated;
    mapping(address => WhitelistUser) public Whitelist;
    uint256[] public vestingPortionsUnlockTime;
    uint256[] public vestingPercentPerPortion;
    Tier[] public tierIdToTier;
    uint256 public totalTierWeight;

    modifier onlySaleOwner() {
        require(msg.sender == sale.saleOwner, "OnlySaleOwner");
        _;
    }

    modifier onlyAdmin() {
        require(
            msg.sender == admin ,
            "Only admin can call this function."
        );
        _;
    }


    constructor(
        address _admin, 
        address _allocationStaking)  {
            require(_admin != address(0));
            require(_allocationStaking != address(0));
            admin = _admin;
            factory = ISalesFactory(msg.sender);
            allocationStakingContract = IAllocationStaking(_allocationStaking);
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
        require(sale.isCreated, "Safeguard for making sure setSaleParams get first called.");

        uint256 sum;

        for (uint256 i = 0; i < _unlockingTimes.length; i++) {
            vestingPortionsUnlockTime.push(_unlockingTimes[i]);
            vestingPercentPerPortion.push(_percents[i]);
            sum += _percents[i];
        }

        require(sum == 100, "Percent distribution issue.");
    }

    function setSaleParams(
        address _token,
        address _saleOwner,
        uint256 _tokenPriceInBUSD,
        uint256 _amountOfTokensToSell,
        uint256 _saleStart,
        uint256 _saleEnd,
        uint256 _tokensUnlockTime,
        uint256 _minimumTokenDeposit
    ) external onlyAdmin {
        require(!sale.isCreated, "Sale created.");
        require(
            _saleOwner != address(0),
            "owner can`t be 0."
        );
        require(
            _tokenPriceInBUSD != 0 &&
                _amountOfTokensToSell != 0 &&
                _saleEnd > block.timestamp &&
                _tokensUnlockTime > block.timestamp,
            "Bad input"
        );
        sale.token = IERC20Extented(_token);
        sale.isCreated = true;
        sale.saleOwner = _saleOwner;
        sale.tokenPriceInBUST = _tokenPriceInBUSD;
        sale.amountOfTokensToSell = _amountOfTokensToSell;
        sale.saleEnd = _saleEnd;
        sale.saleStart = _saleStart;
        sale.tokensUnlockTime = _tokensUnlockTime;
        sale.minimumTokenDeposit = _minimumTokenDeposit;
    }

    function setRegistrationTime(
        uint256 _registrationTimeStarts,
        uint256 _registrationTimeEnds
    ) external onlyAdmin {
        require(sale.isCreated, "1");
        require(
            _registrationTimeStarts >= block.timestamp &&
                _registrationTimeEnds > _registrationTimeStarts, "3"
        );
        require(_registrationTimeEnds < sale.saleEnd, "4");


        registration.registrationTimeStarts = _registrationTimeStarts;
        registration.registrationTimeEnds = _registrationTimeEnds;

    }

    function registerForSale() public {

        uint256 stakeAmount = allocationStakingContract.deposited(msg.sender);

        require(tierIdToTier.length > 0, "Need to set Tiers");
        require(tierIdToTier[0].minToStake <= stakeAmount / 1e18 , "Need to stake minimum for current sale");
        require( Whitelist[msg.sender].userAddress != msg.sender, "You are registered");
        require( block.timestamp >= registration.registrationTimeStarts && block.timestamp <= registration.registrationTimeEnds , "Register is closed");
        for (uint256 i = 0; i < tierIdToTier.length; i++) {
            Tier memory t = tierIdToTier[i];
            if( t.minToStake <= stakeAmount && t.maxToStake > stakeAmount){
                WhitelistUser memory u = WhitelistUser({
                userAddress: msg.sender, 
                userTierId: i
                });
                Whitelist[msg.sender] = u;
                registration.numberOfRegistrants++;
                break;
            }
        }
    }
    
    function updateTokenPriceInBUSD(uint256 price) external onlyAdmin {
        require(price > 0, "Price == 0.");
        require(sale.saleStart > block.timestamp, "Sale started");
        sale.tokenPriceInBUST = price;
    }

    function setWhitelistUsers(address [] calldata users, uint256 tierId) public payable onlyAdmin {

         for (uint256 i = 0; i < users.length; i++) {

            WhitelistUser memory u = WhitelistUser({
            userAddress: users[i], 
            userTierId: tierId
            });
            Whitelist[users[i]] = u;
        }
        
    }

    function addTiers(uint256 [] calldata tierWeights, uint256 [] calldata tierPoints)  public onlyAdmin {   
        
        require(tierWeights.length > 0, "Need 1 tier");
        require(tierWeights.length == tierPoints.length, "nedd same length");


        for (uint256 i = 0; i < tierWeights.length; i++) {
            require( 
                tierWeights[i] > 0,
                "weight > 0"
            );

            totalTierWeight = totalTierWeight + tierWeights[i];

            uint256 maxToStake = tierPoints.length - 1 > i ? tierPoints[i+1] : 2**256 - 1;

            Tier memory t = Tier({
                participants: 0,
                tierWeight: tierWeights[i],
                BUSTDeposited: 0,
                minToStake: tierPoints[i],
                maxToStake: maxToStake
            });
            tierIdToTier.push(t);
        }

     
    }


    function depositTokens() external onlySaleOwner  {
        require(
            !tokensDeposited, "Deposit only once"
        );
        tokensDeposited = true;
        sale.token.safeTransferFrom(
            msg.sender,
            address(this),
            sale.amountOfTokensToSell
        );
    }

    function participate(uint256 amount) 
    external 
    payable 
    {
        require(sale.isCreated, "Wait sale create");

        require( block.timestamp >= sale.saleStart && block.timestamp <= sale.saleEnd , "Sale not active");

        require(!isParticipated[msg.sender], "participate only once.");

        require(msg.sender == tx.origin, "Only direct calls");


        require(amount > 0, "Can't buy 0 tokens");

        require((amount / (10 ** BUSDToken.decimals())) % 2 == 0, "Amount need to be divide by 2");

        require( Whitelist[msg.sender].userAddress != address(0), "User must be in white list" );

        require(amount >= sale.minimumTokenDeposit, "Can't deposit less than minimum"  );

        uint256 _tierId = Whitelist[msg.sender].userTierId;
        sale.totalBUSDRaised = sale.totalBUSDRaised + amount;

        bool[] memory _isPortionWithdrawn = new bool[](
            vestingPortionsUnlockTime.length
        );

        Participation memory p = Participation({
            amountPaid: amount,
            timeParticipated: block.timestamp,
            tierId: _tierId,
            isTokenLeftWithdrawn: false,
            isPortionWithdrawn: _isPortionWithdrawn
        });

        Tier storage t = tierIdToTier[_tierId];

        t.participants = t.participants + 1;
        t.BUSTDeposited = t.BUSTDeposited + amount;
        userToParticipation[msg.sender] = p;
        isParticipated[msg.sender] = true;
        numberOfParticipants++;

        BUSDToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawTokens(uint256 portionId) external {
        require(
            block.timestamp >= sale.tokensUnlockTime,
            "Tokens cann`t be withdrawn."
        );
        require(portionId < vestingPercentPerPortion.length);

        Participation storage p = userToParticipation[msg.sender];

        if(!p.isTokenLeftWithdrawn){
            withdrawLeftoverForUser(msg.sender);
            p.isTokenLeftWithdrawn = true;
        }

        if (
            !p.isPortionWithdrawn[portionId] &&
            vestingPortionsUnlockTime[portionId] <= block.timestamp
        ) {
            p.isPortionWithdrawn[portionId] = true;
            uint256 amountWithdrawing = calculateAmountWithdrawing(msg.sender, vestingPercentPerPortion[portionId]);

            if(amountWithdrawing > 0) {
                sale.token.safeTransfer(msg.sender, amountWithdrawing);
            }
        } else {
            revert("Tokens withdrawn or portion not unlocked.");
        }
    }

    function withdrawLeftoverForUser(address userAddress) internal  {
        Participation memory p = userToParticipation[userAddress];


        uint256 tokensForUser = calculateAmountWithdrawing(userAddress, 100);

        uint256 leftover = p.amountPaid - tokensForUser * sale.tokenPriceInBUST / 10**sale.token.decimals();

        if(leftover > 0){
            BUSDToken.safeTransfer(msg.sender, leftover);
        }
    }
    

    function withdrawMultiplePortions(uint256 [] calldata portionIds) external {
        uint256 totalToWithdraw = 0;

        Participation storage p = userToParticipation[msg.sender];

        if(!p.isTokenLeftWithdrawn){
            withdrawLeftoverForUser(msg.sender);
            p.isTokenLeftWithdrawn = true;
        }

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
            sale.token.safeTransfer(msg.sender, totalToWithdraw);
        }
    }

    function withdrawEarnings() external onlySaleOwner {
        withdrawEarningsInternal();
    }

    function withdrawLeftover() external onlySaleOwner {
        withdrawLeftoverInternal();
    }


    function withdrawEarningsInternal() internal  {
        require(block.timestamp >= sale.saleEnd);
        require(!sale.earningsWithdrawn);
        sale.earningsWithdrawn = true;
        uint256 totalProfit = sale.totalBUSDRaised;
        BUSDToken.safeTransfer(msg.sender, totalProfit);
    }

    function withdrawLeftoverInternal() internal {
        require(block.timestamp >= sale.saleEnd);
        require(!sale.leftoverWithdrawn);
        sale.leftoverWithdrawn = true;
        uint256 totalTokensSold = calculateTotalTokensSold();
        uint256 leftover = sale.amountOfTokensToSell - totalTokensSold;
        if (leftover > 0) {
            sale.token.safeTransfer(msg.sender, leftover);
        }
    }

    function calculateTotalTokensSold() internal view returns (
            uint256
        ) {
        uint256 totalTokensSold = 0;

        for (uint256 i = 0; i < tierIdToTier.length; i++) {
            Tier memory t = tierIdToTier[i];

            uint256 tokensPerTier = t.tierWeight * sale.amountOfTokensToSell/totalTierWeight;

            if( tokensPerTier * sale.tokenPriceInBUST / 10**sale.token.decimals() <= t.BUSTDeposited ){
                totalTokensSold = totalTokensSold + tokensPerTier;
            } else {
                totalTokensSold =  totalTokensSold + t.BUSTDeposited / sale.tokenPriceInBUST * 10**sale.token.decimals();
            }
        }

        return(totalTokensSold);
    }

    function isWhitelisted()
        external
        view
        returns (
            bool
        )
    {
        return (Whitelist[msg.sender].userAddress == msg.sender);
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

        Tier memory t = tierIdToTier[uint(p.tierId)];

        uint256 tokensForUser = 0;

        uint256 tokensPerTier = t.tierWeight*sale.amountOfTokensToSell/totalTierWeight;

        uint256 maximunTokensForUser = tokensPerTier*tokenPercent/t.participants/100;

        uint256 userTokenWish = p.amountPaid/sale.tokenPriceInBUST * (10**sale.token.decimals())*tokenPercent/100;

        if(maximunTokensForUser >= userTokenWish){
            tokensForUser = userTokenWish;
        }else{
            tokensForUser = maximunTokensForUser;
        }

        return (tokensForUser);
    }

    function calculateAmountWithdrawingPortionPub(address userAddress, uint256 tokenPercent) public view returns (
            uint256
        ) {
        
        Participation memory p = userToParticipation[userAddress];

        Tier memory t = tierIdToTier[uint(p.tierId)];

        uint256 tokensPerTier = t.tierWeight * sale.amountOfTokensToSell/totalTierWeight;

        uint256 tokensForUser = tokensPerTier*tokenPercent/t.participants/100;

        return (tokensForUser);
    }
}