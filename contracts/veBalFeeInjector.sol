// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces.sol";


/**
 * @title bb-e-usd ARB
 * @author 0xtritum.eth
 * @notice Handles a 1 time permissioned arbitrag of bb-eusd
 */
contract bbeUSD_arb is ConfirmedOwner, Pausable {
  event keeperRegistryUpdated(address oldAddress, address newAddress);

  address public  bbeusd;

  uint256 public lastRunTimeCurser;
  IERC20[] public managedTokens;
  bool public half;
  IFeeDistributor public feeDistributor;
  bytes constant emptyBytes  = bytes("");

    /**
   * @param _keeperRegistry The address of the keeper registry contract
   * @param _feeDistributor The address of the veBAL fee distributor
   * @param _tokens A list of tokens to handle.
   */
  constructor(address _keeperRegistry, address _feeDistributor, IERC20[] memory _tokens) ConfirmedOwner(msg.sender)  {
    setKeeperRegistry(_keeperRegistry);
    feeDistributor = IFeeDistributor(_feeDistributor);
    setTokens(_tokens);
    half = true; // half on first run
  }

  /*
   * @notice Get list of addresses that are underfunded and return keeper-compatible payload
   * @return upkeepNeeded signals if upkeep is needed, performData is an abi encoded list of addresses that need funds required by chainlink.  It is not used for anything.
   */
  function checkUpkeep(bytes calldata)
    external
    view
    whenNotPaused
    returns (bool upkeepNeeded, bytes memory performData)
  {
    for(uint i=0; i<managedTokens.length; i++){
      if (managedTokens[i].balanceOf(address(this)) > 0){
        upkeepNeeded = true;
      }
      if (lastRunTimeCurser >= feeDistributor.getTimeCursor()) { //Not time yet
        upkeepNeeded = false;
      }
    }
    return (upkeepNeeded, emptyBytes);
  }

 /*
  * @notice Pay out bribs with prechecks for the keeper and no prechecks for the owner.
  * @param performData Required by the chainlink keeper system but not used, can be anything.
  */
  function performUpkeep(bytes calldata performData) external  onlyKeeperRegistry whenNotPaused {
    _payFees();
  }

   /*
  * @notice  Owner callable function to pay a specified amount as bribes regardless of if the system thinks bribs have already been posted this round.  Note that this operation flips the half bit.  If you don't want it flipped you should use setHalf to flip it back.
  * @param amounts A list of amounts to brib, orders in the same order as managedTokens.
  */
  function payFeesAmounts(uint256[] calldata amounts) external onlyOwner whenNotPaused {
    feeDistributor.depositTokens(managedTokens, amounts);
    emit feesPaid(tokens, amounts, timeCurser, half);
    half = !half;
    lastRunTimeCurser = IFeeDistributor.getTimeCursor();
  }


  /*
 * @notice Internal function to do process bribs based on half and balances in the contract.  Will run if any token in the list has a balance in the contract.  Only runs once per timecursor change.
 */
  function _payFees() internal  whenNotPaused {
    uint256 timeCurser = feeDistributor.getTimeCursor();
    require(lastRunTimeCurser < timeCurser || msg.sender == owner(), "TimeCurser hasn't changed.  Already ran once this epoch.");
    IERC20[] memory tokens = managedTokens;
    bool didSomething;
    uint256[] memory amounts = new uint256[](tokens.length);
    uint256 amount;
    for(uint i=0; i<tokens.length; i++){
      if(half){
        amount = tokens[i].balanceOf(address(this))/2;
      } else {
        amount = tokens[i].balanceOf(address(this));
      }
      if(amount > 0){
        didSomething = true;
        amounts[i] = amount;
      }
    }
    require(didSomething == true, "No available tokens to brib.");
    feeDistributor.depositTokens(managedTokens, amounts);
    emit feesPaid(tokens, amounts, timeCurser, half);
    half = !half;
    lastRunTimeCurser = timeCurser;
  }

  /**
   * @notice Withdraws the contract balance
   * @param amount The amount of eth (in wei) to withdraw
   * @param payee The address to pay
   */
  function withdraw(uint256 amount, address payable payee) external onlyOwner {
    if (payee == address(0)) {
      revert("zero address");
    }
    payee.transfer(amount);
  }

  /**
   * @notice Sweep the full contract's balance for a given ERC-20 token
   * @param token The ERC-20 token which needs to be swept
   * @param payee The address to pay
   */
  function sweep(address token, address payee) external onlyOwner {
    uint256 balance = IERC20(token).balanceOf(address(this));
    emit ERC20Swept(token, payee, balance);
    SafeERC20.safeTransfer(IERC20(token), payee, balance);
  }


   /**
   * @notice Sets the list of fee tokens to operate on
   * @param tokens the list of addresses to distribute
   */
  function setTokens(IERC20[] memory tokens) public onlyOwner {
    require(tokens.length >= 1, "Must provide at least once token");
    emit tokensSet(tokens);
    for(uint i=0; i < tokens.length; i++){
      tokens[i].approve(address(feeDistributor), 2**128);
    }
    managedTokens = tokens;
  }

 /*
 * @notice Returns the list of managed tokens as addresses instead of ERC20 objects
 */
  function getTokens() public view returns (address[] memory) {
    IERC20[] memory tokens = managedTokens;
    address[] memory addresses = new address[](tokens.length);
    for (uint i=0; i<managedTokens.length; i++) {
      addresses[i] = address(managedTokens[i]);
    }
    return addresses;
  }

  /**
   * @notice Sets the keeper registry address
   */
  function setKeeperRegistry(address _keeperRegistry) public onlyOwner {
    emit keeperRegistryUpdated(keeperRegistry, _keeperRegistry);
    keeperRegistry = _keeperRegistry;
  }

  /**
   * @notice Unpauses the contract
   */
  function unpause() external onlyOwner {
    _unpause();
  }

  modifier onlyKeeperRegistry() {
    if (msg.sender != keeperRegistry && msg.sender != owner()) {
      require(false, "Only the Registry or the Owner can do that");
    }
    _;
  }


}