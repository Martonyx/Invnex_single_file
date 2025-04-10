//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;


abstract contract Utils {

  /* ================== ERRORS =================== */
  
  error Unauthorized();
  error NotAnAdminWallet();
  error NotAuthorizedToBuyThisToken();
  error TokenAlreadyListed();
  error InvalidPrice();
  error TokenNotListed();
  error IcoStillOnSale();
  error USYTtransferFailed();
  error NotReadyForClaim();
  error CustomTokenTransferFailed();
  error InvalidAddress();
  error NoUSYTtoClaim();
  error InitialSupplyNotComplete();
  error NoGasfeesToWithdraw();
  error NotInEmergencyPeriod();
  error cashTokensNotFullyClaimed();
  error TokenStill_Listed();
  error TokenCashBalanceHasBeenClaimed();
  error UnsuccessfulTokenCannotBeClaimed();
  error TokenNotDeployed();
  error MustBeGreaterThanZero();
  error InvalidLimits();
  error InvnexMarkertAddressHasNotBeenSet();
  error NoEscrowedTokensToClaim();
  error USYTapprovalFailed();
  error IcoHasNotStarted();
  error IcoHasEnded();
  error InsufficientTokens();
  error InsufficientCashBalance();
  error InsufficientSupply();
  error GoalIsNotInRange();
  error GoalReached();
  error GoalHasNotBeenReached();
  error ICOAlreadyFinalized();
  error NoTokensLeftToTransfer();
  error ZeroAddress();
  error FeeIsNotInRange();
  error NotInRange();
  error OwnerHasClaimed();
  error ClaimableAfterGracePeriod();
  error InAchiveMode();
  error NameTooLong();
  error SymbolTooLong();
  error SupplyOverflow();
  error NotAnAdmin();
  error AlreadyAdmin();
  error PageTooLarge();
  error ERC20_AlreadyInitialized();
  error ERC20_EmptyName();
  error ERC20_EmptySymbol();

  /* ================== STRUCTS =================== */

  struct TokenInfo {
    string name;
    string symbol;
    address tokenAddress;
    address tokenOwner;
    uint256 tokenId;
    uint256 icoStartTime;
    uint256 icoEndTime;
    uint256 icoEndedAt;
    uint256 initialSupply;
    uint256 goalPercentage;
    uint256 tokenCashBalance;
    uint256 tokenPrice;
    uint256 icoPercentageFee;
    bool isListed;
    bool isReadyToClaim;
    bool hasBeenPaid;
    bool icoFinalized;
  }

  struct TokenDetails {
    uint256 tokenId;
    string tokenName;
  }

  struct EscrowEntry {
    uint256 tokenAmount;
    uint256 cashTokenAmount;
  }

  struct TokenBalance {
    uint256 tokenId;
    uint256 balance;
  }

  struct TokenAllowance {
    mapping(address => uint256) indexPlusOne;
    address[] allowedList;
  }

}