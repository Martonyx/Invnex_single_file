//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20Token} from "./ERC20Token.sol";
import {Utils} from "../src/utils/InvnexUtils.sol";
import {USYT} from "./Invnex_token/USYT.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract Invnex is Utils {

    using Clones for address;

    /* ================== STATE VARIABLES =================== */

    address public owner;
    USYT public immutable usyt;
    uint256 public tokenInfoCount;
    uint256 public icoPlatformFees;
    uint256 public gracePeriod = 1814400;
    uint256[] private successfulIcoTokens;
    address public immutable tokenImplementation;

    /* ================== MAPPINGS =================== */

    mapping(uint256 => TokenInfo) private deployedTokens;
    mapping(uint256 => mapping(address => bool)) public allowedAddresses;
    mapping(uint256 => mapping(address => EscrowEntry)) public escrowedTokens;
    mapping(uint256 => address[]) public buyersForToken;
    mapping(uint256 => uint256) public currentSupply;
    mapping(address => bool) public adminWallets;
    mapping(uint256 => bool) public isListedTokens;
    mapping(address => uint256[]) public tokensOwnedByBuyer;
    mapping(uint256 => mapping(address => uint256)) private buyerIndex;
    mapping(address => mapping(uint256 => uint256)) public buyersForTokenAndAmounts;

    /* ================== EVENTS =================== */

    event TokenDeployed(address indexed tokenAddress, uint256 indexed newTokenId, address indexed creator);
    event TokenBought(address indexed tokenAddress, address indexed buyer, uint256 amount);
    event TokenSoldBack(uint256 tokenId, address indexed buyer, uint256 anount, uint256 refund);
    event TokenBurned(address indexed tokenAddress, uint256 indexed tokenId);
    event TokenListed(address indexed tokenAddress, uint256 indexed tokenId, uint256 tokenPrice);
    event TokenDelisted(address indexed tokenAddress, uint256 indexed tokenId);
    event IcoFinalized(uint256 indexed tokenId, uint256 indexed amount, address indexed owner);
    event Unsubscribed(uint256 indexed tokenId, address indexed user, uint256 amountRefunded);

    /* ======================= MODIFIERS ======================= */

    /**
     * @notice Allow only approved borrower addresses
     */
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier onlyAdmin() {
        if (!adminWallets[msg.sender]) revert NotAnAdminWallet();
        _;
    }

    modifier isTokenDeployed(uint256 tokenId) {
        _isTokenDeployed(tokenId);
        _;
    }
 
    modifier onlyAllowed(uint256 tokenId) {
        if (!allowedAddresses[tokenId][msg.sender]) revert NotAuthorizedToBuyThisToken();
        _;
    }

    modifier duringICO(uint256 tokenId) {
        if (deployedTokens[tokenId].icoStartTime == 0) revert IcoHasNotStarted();
        if (block.timestamp > deployedTokens[tokenId].icoEndTime) revert IcoHasEnded();
        if (deployedTokens[tokenId].isReadyToClaim) revert GoalReached();
        _;
    }

    modifier afterICO(uint256 tokenId) {
        if (block.timestamp < deployedTokens[tokenId].icoEndTime) revert IcoStillOnSale();
        _;
    }

    modifier atEmergencyICOStop(uint256 tokenId) {
        if(deployedTokens[tokenId].icoEndTime != 0 && getRemainingSupply(tokenId) != 0) revert NotInEmergencyPeriod();
        _;
    }

    /* ======================= FUNCTIONS ======================= */

    constructor(address _usyt) {
        tokenImplementation = address(new ERC20Token());
        owner = msg.sender;
        usyt = USYT(_usyt);
    }

    /**
     * @notice Deploys a new ERC20 token with optimized gas usage
     * @dev Uses clone factory pattern for cheaper deployments and adds input validation
     * @param _name Token name (max 32 bytes for gas savings)
     * @param _symbol Token symbol (max 8 bytes)
     * @param _tokenOwner Non-zero address that will control the token
     * @param _initialSupply Supply in whole units (automatically converted to wei)
     */
    function deployToken(
        string calldata _name,
        string calldata _symbol,
        address _tokenOwner,
        uint256 _initialSupply
    ) external onlyOwner {
        if (_tokenOwner == address(0)) revert ZeroAddress();
        if (_initialSupply == 0) revert MustBeGreaterThanZero();
        if (bytes(_name).length > 32) revert NameTooLong();
        if (bytes(_symbol).length > 8) revert SymbolTooLong();

        uint256 adjustedSupply= _initialSupply * 1 ether;
        bytes32 salt = keccak256(abi.encodePacked(_name, _symbol, block.timestamp, _tokenOwner));
        address clone = tokenImplementation.cloneDeterministic(salt);

        ERC20Token(clone).initialize(_name, _symbol, address(this), adjustedSupply);

        uint256 newTokenId = ++tokenInfoCount;
        deployedTokens[newTokenId] = TokenInfo({
            name: _name,
            symbol: _symbol,
            tokenAddress: clone,
            tokenOwner: _tokenOwner,
            tokenId: newTokenId,
            initialSupply: _initialSupply,
            icoStartTime: 0,
            icoEndTime: 0,
            icoEndedAt: 0,
            goalPercentage: 0,
            tokenCashBalance: 0,
            tokenPrice: 0,
            icoPercentageFee: 0,
            isListed: false,
            isReadyToClaim: false,
            icoFinalized: false,
            hasBeenPaid: false
        });

        emit TokenDeployed(clone, newTokenId, _tokenOwner);
    }

    /**
     * @notice Lists a deployed token for sale by setting its price and ICO duration.
     * @dev This function can only be called by the contract owner and only for tokens that have been deployed but not yet listed.
     * @param tokenId The ID of the token to be listed.
     * @param _tokenPrice The price of the token to be set for the ICO.
    */
    function listToken(
        uint256 tokenId,
        uint256 _tokenPrice,
        uint256 icoDurationInSecs,
        uint256 _icoPercentageFee,
        uint256 _goalPercentage
    ) public onlyOwner isTokenDeployed(tokenId) {
        TokenInfo storage token = deployedTokens[tokenId];

        if (token.tokenPrice > 0) revert TokenAlreadyListed();
        if (_tokenPrice == 0) revert InvalidPrice();
        if(_goalPercentage == 0 || _goalPercentage > 100 ) revert GoalIsNotInRange();

        token.icoStartTime = block.timestamp;
        token.tokenPrice = _tokenPrice;
        token.icoPercentageFee = _icoPercentageFee;
        token.goalPercentage = _goalPercentage;
        token.icoEndTime = block.timestamp + icoDurationInSecs;
        token.isListed = true;
        isListedTokens[tokenId] = true;

        emit TokenListed(token.tokenAddress, tokenId, _tokenPrice);
    }

    /**
     * @notice Delists a previously listed token, removing it from sale.
     * @dev This function can only be called by the contract owner.
     * @param tokenId The ID of the token to be delisted.
    */
    function delistToken(uint256 tokenId) public onlyOwner {
        if(!isListedTokens[tokenId]) revert TokenNotListed();
        TokenInfo storage token = deployedTokens[tokenId];

        token.tokenPrice = 0;
        token.icoEndTime = 0;
        token.icoPercentageFee = 0;
        token.isListed = false;
        isListedTokens[tokenId] = false;

        emit TokenDelisted(token.tokenAddress, tokenId);
    }

    /**
     * @notice Allows an allowed user to purchase tokens during the ICO by transferring the equivalent amount of usyt.
     * @dev This function can only be called by allowed users, for deployed tokens, and only during the ICO period.
     * @param tokenId The ID of the token being purchased.
     * @param tokenAmount The number of tokens the user wants to purchase.
    */
    function buyToken(uint256 tokenId, uint256 tokenAmount) public onlyAllowed(tokenId) isTokenDeployed(tokenId) duringICO(tokenId) {
        TokenInfo storage token = deployedTokens[tokenId];

        if (!token.isListed) revert TokenNotListed();
        if (tokenAmount <= 0 ) revert MustBeGreaterThanZero();

        uint256 cashTokenAmount = _calculateCASHAmount(tokenId, tokenAmount);

        bool tokenTransfered = usyt.transferFrom(msg.sender, address(this), cashTokenAmount);
        if (!tokenTransfered) revert USYTtransferFailed();

        token.tokenCashBalance += cashTokenAmount;

        escrowedTokens[tokenId][msg.sender].tokenAmount += tokenAmount;
        escrowedTokens[tokenId][msg.sender].cashTokenAmount += cashTokenAmount;

        currentSupply[tokenId] += tokenAmount;
        if (buyersForTokenAndAmounts[msg.sender][tokenId] == 0) {
            buyersForToken[tokenId].push(msg.sender);
            buyerIndex[tokenId][msg.sender] = buyersForToken[tokenId].length - 1;
            tokensOwnedByBuyer[msg.sender].push(tokenId);
        }
        buyersForTokenAndAmounts[msg.sender][tokenId] += tokenAmount;

        (,,,, bool isGoal) = getIcoProgress(tokenId);
        if (isGoal) {
            token.isReadyToClaim = true;
            token.icoEndedAt = block.timestamp;
            token.isListed = false;
            isListedTokens[tokenId] = false;
        }

        emit TokenBought(token.tokenAddress, msg.sender, tokenAmount);
    }

    /**
     * @notice Allows an allowed user to claim their escrowed tokens after the ICO has concluded.
     * @dev This function can only be called for deployed tokens, by users who are allowed, and only after the ICO has ended.
     * @param tokenId The ID of the token for which the user is claiming their escrowed tokens.
    */
    function claimEscrowedTokens(uint256 tokenId) external isTokenDeployed(tokenId) onlyAllowed(tokenId) afterICO(tokenId) {
        if (getRemainingSupply(tokenId) != 0) revert UnsuccessfulTokenCannotBeClaimed();
        address buyer = msg.sender;
        uint256 tokenAmount = escrowedTokens[tokenId][buyer].tokenAmount;

        if (tokenAmount == 0) revert NoEscrowedTokensToClaim();

        delete escrowedTokens[tokenId][buyer];

        ERC20Token token = ERC20Token(deployedTokens[tokenId].tokenAddress);
        bool tokenTransfered = token.transfer(buyer, tokenAmount);
        if(!tokenTransfered) revert CustomTokenTransferFailed();
    }

    /**
     * @notice Unsubscribes a user from receiving tokens during an ICO emergency stop and refunds their escrowed tokens.
     * @dev This function calls the `unsubscribeTokens` function and can only be executed during an ICO emergency stop.
     * @param tokenId The ID of the token from which the user wants to unsubscribe.
    */
    function _unsubscribeTokensAtEmergency(uint256 tokenId) external isTokenDeployed(tokenId) atEmergencyICOStop(tokenId) {
        _unsubscribe(tokenId);
    }

    /**
     * @notice Unsubscribes a user from receiving tokens during an ICO and refunds their escrowed tokens.
     * @dev This function can only be called during the ICO period and only if the token has been deployed.
     * @param tokenId The ID of the token from which the user wants to unsubscribe.
    */
    function _unsubscribe(uint256 tokenId) internal {
        address buyer = msg.sender;
        uint256 _tokenAmount = escrowedTokens[tokenId][buyer].tokenAmount;
        uint256 cashTokenAmount = escrowedTokens[tokenId][buyer].cashTokenAmount;

        if (cashTokenAmount <= 0) revert NoUSYTtoClaim();
        delete escrowedTokens[tokenId][buyer];

        currentSupply[tokenId] -= _tokenAmount;
        TokenInfo storage token = deployedTokens[tokenId];
        token.tokenCashBalance -= cashTokenAmount;

        buyersForTokenAndAmounts[buyer][tokenId] -= _tokenAmount;
        _removeBuyerFromTokenList(tokenId, buyer);
        _removeTokenFromBuyerList(buyer, tokenId);

        bool tokenTransferred = usyt.transfer(buyer, cashTokenAmount);
        if (!tokenTransferred) revert USYTtransferFailed();
        emit Unsubscribed(tokenId, msg.sender, cashTokenAmount);
    }

    function unsubscribeTokens(uint256 tokenId) public isTokenDeployed(tokenId) duringICO(tokenId) {
        _unsubscribe(tokenId);
    }

    /**
    * @notice Allows users to unsubscribe and reclaim their usyt if the project owner did not claim the money after 21 days 
    * of successful ICO
    * @param tokenId  the Id of the token the bought
    */
    function unsubscribeTokensAfterGracePeroid(uint256 tokenId) public isTokenDeployed(tokenId) {
        TokenInfo storage tokenInfo = deployedTokens[tokenId];
        if(!tokenInfo.isReadyToClaim) revert GoalHasNotBeenReached();
        if(block.timestamp < tokenInfo.icoEndedAt + 21 days) revert ClaimableAfterGracePeriod();
        if(tokenInfo.hasBeenPaid) revert OwnerHasClaimed();
        _unsubscribe(tokenId);
    }

    /**
     * @notice Allows a user to partially sell back their subscribed tokens before the ICO ends.
     * @dev Users can reclaim a proportional amount of their USYT by selling back some of their tokens.
     *      This function only works during the ICO period.
     * @param tokenId The ID of the token being sold back.
     * @param amount The amount of tokens the user wants to sell back.
    */
    function sellBackTokens(uint256 tokenId, uint256 amount) public isTokenDeployed(tokenId) duringICO(tokenId) {
        address buyer = msg.sender;
        uint256 escrowedAmount = escrowedTokens[tokenId][buyer].tokenAmount;
        uint256 cashTokenAmount = escrowedTokens[tokenId][buyer].cashTokenAmount;

        if (amount > escrowedAmount) revert InsufficientTokens();
        
        uint256 refund = (cashTokenAmount * amount) / escrowedAmount;

        escrowedTokens[tokenId][buyer].tokenAmount -= amount;
        escrowedTokens[tokenId][buyer].cashTokenAmount -= refund;
        
        currentSupply[tokenId] -= amount;
        
        TokenInfo storage token = deployedTokens[tokenId];
        token.tokenCashBalance -= cashTokenAmount;

        bool tokenTransferred = usyt.transfer(buyer, refund);
        if (!tokenTransferred) revert USYTtransferFailed();

        emit TokenSoldBack(tokenId, buyer, amount, refund);
    }

    /**
     * @notice Allows the project owner to claim the funds raised from the ICO for the specified token.
     * @dev This function can only be called by the token owner and if the funds are ready for claim.
     * @param tokenId The ID of the token for which the project funds are being claimed.
    */
    function claimProjectMoney(uint256 tokenId) public isTokenDeployed(tokenId) {
        TokenInfo storage tokenInfo = deployedTokens[tokenId];
        
        if (tokenInfo.tokenOwner != msg.sender) revert Unauthorized();
        if (!tokenInfo.isReadyToClaim) revert NotReadyForClaim();
        if (tokenInfo.hasBeenPaid) revert TokenCashBalanceHasBeenClaimed();
        if (tokenInfo.icoEndedAt + gracePeriod < block.timestamp) revert InAchiveMode();
        uint256 totalCASHBalance = tokenInfo.tokenCashBalance;
        uint256 _icoPercentageFee = tokenInfo.icoPercentageFee;

        uint256 icoFeePercent_ = (totalCASHBalance * _icoPercentageFee) / 100;
        uint256 netBalance = totalCASHBalance - icoFeePercent_;
        icoPlatformFees += icoFeePercent_;

        tokenInfo.hasBeenPaid = true;
        totalCASHBalance = 0;
        successfulIcoTokens.push(tokenId);

        bool tokenTransfered = usyt.transfer(owner, netBalance);
        if(!tokenTransfered) revert USYTtransferFailed();
        
    }

    /**
     * @notice Burns the specified token, removing it from circulation and deleting its associated data.
     * @dev This function can only be called by the owner, during an ICO emergency stop, and after the token is no longer listed.
     * @param tokenId The ID of the token to be burned.
    */
    function burnToken(uint256 tokenId) public onlyOwner isTokenDeployed(tokenId) atEmergencyICOStop(tokenId) {
        if(isListedTokens[tokenId]) revert TokenStill_Listed();
        TokenInfo storage tokenInfo = deployedTokens[tokenId];
        ERC20Token token = ERC20Token(tokenInfo.tokenAddress);

        if (token.balanceOf(address(this)) != tokenInfo.initialSupply * 1e18) revert InitialSupplyNotComplete();
        if (tokenInfo.tokenCashBalance != 0) revert cashTokensNotFullyClaimed();

        uint256 unsoldTokens = token.totalSupply();

        token.burn(unsoldTokens);
        delete deployedTokens[tokenId];

        emit TokenBurned(tokenInfo.tokenAddress, tokenId);
    }

    /**
     * @notice Allows the contract owner to withdraw accumulated gas fees in the form of usyt.
     * @dev This function can only be called by the contract owner and resets the gas fee balance to zero after withdrawal.
    */
    function withdrawUSYTFees() public onlyOwner {
        if(icoPlatformFees <= 0) revert NoGasfeesToWithdraw();
    
        uint256 feesToTransfer = icoPlatformFees;
        icoPlatformFees = 0; 
        bool tokenTransfered = usyt.transfer(msg.sender, feesToTransfer);
        if(!tokenTransfered) revert USYTtransferFailed();
    } 

    /**
     * @notice Adds an address to the list of allowed addresses for a specific token.
     * @dev This function can only be called by an admin and for a token that has been deployed.
     * @param tokenId The ID of the token for which the address is being allowed.
     * @param addresses An array of addresses to add to the allowed list for the specified token ID.
    */
    function addToAllowedAddresses(uint256 tokenId, address[] memory addresses) public onlyAdmin isTokenDeployed(tokenId) {
        for (uint256 i = 0; i < addresses.length; i++) {
            address addr = addresses[i];
            if (addr == address(0)) revert InvalidAddress();
            allowedAddresses[tokenId][addr] = true;
        }
    }

    /**
     * @notice Removes an address from the list of allowed addresses for a specific token.
     * @dev This function can only be called by an admin and for a token that has been deployed.
     * @param tokenId The ID of the token for which the address is being removed.
     * @param addresses The addresses to be removed from the allowed list.
    */
    function removeFromAllowedAddresses(uint256 tokenId, address[] memory addresses) public onlyAdmin isTokenDeployed(tokenId) {
        for (uint256 i = 0; i < addresses.length; i++) {
            address addr = addresses[i];
            if (addr == address(0)) revert InvalidAddress();
            allowedAddresses[tokenId][addr] = false;
        }
    }

    /**
     * @notice Adds an address to the list of admin addresses.
     * @dev This function can only be called by the contract owner.
     * @param adminAddress The address of the new admin to be added.
    */
    function addAdmin(address adminAddress) public onlyOwner {
        adminWallets[adminAddress] = true;
    }

    /**
     * @notice Removes an address from the list of admin addresses.
     * @dev This function can only be called by the contract owner.
     * @param adminAddress The address of the admin to be removed.
    */
    function removeAdmin(address adminAddress) public onlyOwner {
        adminWallets[adminAddress] = false;
    }

    /**
     * @notice Transfers ownership of the contract to a new address.
     * @dev This function can only be called by the current owner. The new owner address cannot be the zero address.
     * @param newOwner The address of the new owner to be set.
    */
    function transferOwnership(address newOwner) public onlyOwner {
        if(newOwner == address(0)) revert InvalidAddress();
        owner = newOwner;
    }
    
    /**
     * @notice Sets the ico Percentage fees for an ICO in percentage.
     * @dev This function can only be called by the contract owner.
     * @param _icoFeePercent The fee percentage to be set for the ICO transactions.
     * @param tokenId tokenId of the token
    */
    function setIcoPercentageFee(uint256 tokenId, uint256 _icoFeePercent) public onlyOwner {
        if(!isListedTokens[tokenId]) revert TokenNotListed();
        if(_icoFeePercent == 0 || _icoFeePercent > 100 ) revert FeeIsNotInRange();

        TokenInfo storage token = deployedTokens[tokenId];
        token.icoPercentageFee = _icoFeePercent;
    }

    /**
     * @notice Transfers remaining tokens to owner if ICO goal is reached
     * @param tokenId The ID of the token to finalize
     */
    function finalizeIco(uint256 tokenId) external isTokenDeployed(tokenId) onlyOwner {
        TokenInfo storage tokenInfo = deployedTokens[tokenId];
        if(!tokenInfo.isReadyToClaim) revert GoalHasNotBeenReached();        
        if(tokenInfo.icoFinalized) revert ICOAlreadyFinalized();
        
        uint256 remainingSupply = getRemainingSupply(tokenId);
        if(remainingSupply <= 0) revert NoTokensLeftToTransfer();
        
        address tokenAddress = deployedTokens[tokenId].tokenAddress;
        ERC20Token token = ERC20Token(tokenAddress);
        
        token.transfer(owner, remainingSupply);        
        tokenInfo.icoFinalized = true;
        currentSupply[tokenId] = deployedTokens[tokenId].initialSupply;
        
        emit IcoFinalized(tokenId, remainingSupply, owner);
    }

    function getIcoProgress(uint256 tokenId) public view isTokenDeployed(tokenId) returns (
        uint256 initialSupply,
        uint256 remainingSupply,
        uint256 soldAmount,
        uint256 progressPercentage,
        bool isGoalReached
    ) {
        TokenInfo memory tokenInfo = deployedTokens[tokenId];    
        initialSupply = tokenInfo.initialSupply;
        remainingSupply = getRemainingSupply(tokenId);
        soldAmount = initialSupply - remainingSupply;
        progressPercentage = (soldAmount * 100) / initialSupply;
        isGoalReached = progressPercentage >= tokenInfo.goalPercentage;
        
        return (initialSupply, remainingSupply, soldAmount, progressPercentage, isGoalReached);
    }

    /**
     * @notice Retrieves the remaining supply of tokens for a specific token ID.
     * @dev This function calculates the remaining supply by subtracting the current supply from the initial supply.
     * @param tokenId The ID of the token for which the remaining supply is being queried.
     * @return The number of tokens remaining for the specified token ID.
    */
    function getRemainingSupply(uint256 tokenId) public view isTokenDeployed(tokenId) returns (uint256) {
        uint256 _initialSupply = deployedTokens[tokenId].initialSupply;
        return _initialSupply - currentSupply[tokenId];
    }

    /**
     * @notice Returns all tokens and balances owned by a specific user
     * @dev Combines data from both mappings to provide a comprehensive view
     * @param user The address of the user to query
     * @return TokenBalance[] Array of token IDs and their corresponding balances
     */
    function getUserTokenBalances(address user) public view returns (TokenBalance[] memory) {
        uint256[] memory ownedTokenIds = tokensOwnedByBuyer[user];
        
        TokenBalance[] memory balances = new TokenBalance[](ownedTokenIds.length);
        for (uint256 i = 0; i < ownedTokenIds.length; i++) {
            uint256 tokenId = ownedTokenIds[i];
            balances[i] = TokenBalance({
                tokenId: tokenId,
                balance: buyersForTokenAndAmounts[user][tokenId]
            });
        }
        return balances;
    }

    /**
     * @notice Returns a range of successful ICO tokens with pagination
     * @dev Prevents out-of-gas errors by allowing chunked retrieval
     * @param lowerLimit Starting index (inclusive)
     * @param upperLimit Ending index (exclusive)
     */
    function getSuccessfulIcoTokens(uint256 lowerLimit, uint256 upperLimit) 
        public 
        view 
        returns (uint256[] memory chunk, uint256 totalTokens) 
    {
        totalTokens = successfulIcoTokens.length;
        if (upperLimit > totalTokens) upperLimit = totalTokens;
        if (lowerLimit >= upperLimit) {
            return (new uint256[](0), totalTokens);
        }

        chunk = new uint256[](upperLimit - lowerLimit);
        for (uint256 i = lowerLimit; i < upperLimit; i++) {
            chunk[i - lowerLimit] = successfulIcoTokens[i];
        }
        return (chunk, totalTokens);
    }

    /**
     * @notice Retrieves the list of addresses that have purchased a specific token.
     * @dev This function can only be called for deployed tokens.
     * @param tokenId The ID of the token for which the buyers' addresses are requested.
    */
    function getBuyersForToken(uint256 tokenId) public view isTokenDeployed(tokenId) returns (address[] memory) {
        return buyersForToken[tokenId];
    }

    /**
     * @notice Returns paginated details of listed tokens
     * @dev Efficiently handles sparse arrays by pre-counting and tight packing
     * @param lowerLimit Starting index (inclusive, 1-based)
     * @param upperLimit Ending index (inclusive)
     */
    function getListedTokensWithCount(uint256 lowerLimit, uint256 upperLimit)
        public
        view
        returns (TokenDetails[] memory tokens, uint256 totalListed)
    {
        if (lowerLimit == 0 || upperLimit < lowerLimit) revert InvalidLimits();
        if (upperLimit > tokenInfoCount) upperLimit = tokenInfoCount;
        
        for (uint256 i = lowerLimit; i <= upperLimit; i++) {
            if (isListedTokens[i]) totalListed++;
        }
        
        tokens = new TokenDetails[](totalListed);
        uint256 index;
        
        for (uint256 i = lowerLimit; i <= upperLimit; i++) {
            if (isListedTokens[i]) {
                tokens[index++] = TokenDetails(i, deployedTokens[i].name);
            }
        }
    }
    
    /**
     * @notice Returns paginated token details (ID + name)
     * @dev Uses tight packing and proper bounds checking
     * @param lowerLimit Starting index (1-based inclusive)
     * @param upperLimit Ending index (inclusive)
     * @return TokenDetails[] Array of token info in requested range
     */
    function getAllTokenIdsAndNames(uint256 lowerLimit, uint256 upperLimit) 
        public 
        view 
        returns (TokenDetails[] memory) 
    {
        if (lowerLimit == 0 || lowerLimit > upperLimit) revert InvalidLimits();
        if (upperLimit > tokenInfoCount) upperLimit = tokenInfoCount;

        uint256 resultSize = upperLimit - lowerLimit + 1;
        TokenDetails[] memory tokens = new TokenDetails[](resultSize);

        for (uint256 i = 0; i < resultSize; i++) {
            uint256 tokenId = lowerLimit + i;
            tokens[i] = TokenDetails({
                tokenId: tokenId,
                tokenName: deployedTokens[tokenId].name
            });
        }
        return tokens;
    }

    function getTokenInfo(uint256 tokenId) public view isTokenDeployed(tokenId) returns (TokenInfo memory) {
        return deployedTokens[tokenId];
    }

    /* ================== INTERNAL FUNCTIONS =================== */

    function _onlyOwner() internal view {
        if (msg.sender != owner) revert Unauthorized();
    }

    function _isTokenDeployed(uint256 tokenId) internal view {
        if (deployedTokens[tokenId].tokenAddress == address(0)) revert TokenNotDeployed();
    }

    function _calculateCASHAmount(uint256 tokenId, uint256 tokenAmount) internal view returns (uint256) {
        uint256 tokenPrice_ = deployedTokens[tokenId].tokenPrice;
        uint256 tokenPriceInCASH = tokenPrice_ * 10**18;
        return tokenAmount * tokenPriceInCASH;
    }

    function _removeBuyerFromTokenList(uint256 tokenId, address buyer) internal {
        uint256 index = buyerIndex[tokenId][buyer];
        uint256 lastIndex = buyersForToken[tokenId].length - 1;

        if (index != lastIndex) {
            address lastBuyer = buyersForToken[tokenId][lastIndex];
            buyersForToken[tokenId][index] = lastBuyer;
            buyerIndex[tokenId][lastBuyer] = index;
        }
        buyersForToken[tokenId].pop();
        delete buyerIndex[tokenId][buyer];
    }

    function _removeTokenFromBuyerList(address buyer, uint256 tokenId) internal {
        if (buyersForTokenAndAmounts[buyer][tokenId] == 0) {
            uint256 length = tokensOwnedByBuyer[buyer].length;
            for (uint256 i = 0; i < length; i++) {
                if (tokensOwnedByBuyer[buyer][i] == tokenId) {
                    tokensOwnedByBuyer[buyer][i] = tokensOwnedByBuyer[buyer][length - 1];
                    tokensOwnedByBuyer[buyer].pop();
                    break;
                }
            }
        }
    }
}