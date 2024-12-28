# Crowdfunding Contract (StarkNet)

This StarkNet contract implements a crowdfunding mechanism where users can contribute to a campaign with any ERC20 tokens(contract addresss is needed to pass to the contract). Funds are withdrawn to a designated grantee address once the target amount is reached or the campaign deadline is passed.

## Features

*   Users can donate ERC20 tokens to the contract.
*   Contract owner can withdraw funds to the grantee address.
*   Contract owner can reset the contract for a new campaign (after target is met or deadline passes and all funds are withdrawn).
*   Supports any ERC20 token on starknet(default STRK)

## Usage

1.  Deploy the contract with the desired campaign details:
    *   `token` (optional, defaults to STRK token address): Contract address of the ERC20 token used for funding.
    *   `grantee_address`: Address of the beneficiary who will receive the raised funds.
    *   `fund_target`: Target amount to raise in the crowdfunding campaign.
    *   `fund_description`: Description of the campaign (English only).
    *   `deadline`: Unix timestamp representing the campaign end date.
    *   `initial_owner`: Address of the initial contract owner.

2.  Users can call the `fund_to_contract` function to donate STRK tokens to the contract.

3.  The contract owner can call the `withdraw_funds` function to withdraw all collected funds to the grantee address when the target is met or the deadline is reached.

4.  After a successful campaign or withdrawal, the contract owner can call the `reset_fund` function to set up a new campaign with different details. This requires the previous campaign to be completed (target met or deadline passed) and all funds withdrawn.

## Interface

The contract implements the `IFund` interface which defines the following functions:

*   `get_fund_balance`: Returns the current balance of the contract in STRK tokens.
*   `get_fund_target`: Returns the target funding amount for the campaign.
*   `get_fund_description`: Returns the description of the crowdfunding campaign.
*   `get_deadline`: Returns the Unix timestamp for the campaign deadline.
*   `fund_to_contract`: Allows users to donate STRK tokens to the contract.
*   `withdraw_funds`: Allows the contract owner to withdraw all collected funds to the grantee address.
*   `reset_fund`: Allows the contract owner to reset the contract for a new campaign.

## Events

The contract emits several events:

*   `OwnableEvent`: Events related to contract ownership management (inherited from OwnableComponent).
*   `SelfDestructed`: Emitted when the contract is self-destructed, indicating the recipient address and remaining funds.
*   `Transfer`: Emitted when a successful token transfer occurs (e.g., user donation).
*   `TransferFailed`: Emitted when a token transfer fails.
*   `ResetFund`: Emitted when the contract is reset for a new campaign, including details of the new campaign.

## Dependencies

*   OpenZeppelin Ownable: Provides ownership management functionality.
*   OpenZeppelin ERC20: Provides interaction with ERC20 tokens.

## Deployment and Interaction (Example using starkli)

```bash
# Compile the contract
cd packages/snfoundry/contracts
scarb build
# Run the contract test
scarb test

# Deploy the contract 
yarn deploy --network {NETWORK_NAME} //"sepolia" or "mainnet", defaults to "devnet"
