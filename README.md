# Starknet Crowdfunding Platform

A decentralized crowdfunding platform built on StarkNet, enabling users to create and participate in fundraising campaigns using ERC20 tokens. The platform consists of a Cairo smart contract for on-chain logic and a Next.js frontend for user interaction.

## Features

### Smart Contract
* Support for any ERC20 token on StarkNet (currently UI supports STRK and ETH)
* Secure fund management with ownership controls
* Deadline-based campaign management
* Flexible campaign reset functionality
* Transparent fund tracking and withdrawal system
* Role-based access control system

### Access Control System

The platform implements a robust role-based access control system:

#### Admin/Owner Privileges
* Toggle campaign active status (activate/deactivate)
* Withdraw funds when conditions are met
* Reset campaign with new parameters
* View special owner-only UI controls
* Manage campaign core parameters

#### User Permissions
* View campaign details and progress
* Make donations to active campaigns
* View their donation history
* Connect/disconnect wallet

#### Campaign State Restrictions
* Donations only accepted when campaign is active
* Withdrawals only allowed when:
  - Campaign deadline has passed, OR
  - Funding target has been reached
* Campaign reset only possible after:
  - All funds have been withdrawn
  - Previous campaign is completed

#### Smart Contract Validations
* Owner-only function access
* Active status checks
* Deadline enforcement
* Balance verification
* Token approval validation

### Frontend Interface
* Modern, responsive UI built with Next.js and Tailwind CSS
* Real-time campaign progress tracking
* Interactive donation interface
* Countdown timer for campaign deadline
* Dark/Light mode support
* Owner-specific controls for campaign management

## Project Structure

```
scaffold-stark-crowd-funding/
├── packages/
│   ├── nextjs/              # Frontend application
│   │   ├── app/            # Next.js pages and components
│   │   ├── components/     # Reusable UI components
│   │   └── hooks/         # Custom React hooks
│   └── snfoundry/          # Smart contract
│       └── contracts/     # Cairo contract files
```

## Prerequisites

* Node.js (v16 or higher)
* Yarn package manager
* Scarb (for Cairo contract development)
* StarkNet wallet (e.g., ArgentX, Braavos)

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/scaffold-stark-crowd-funding.git
   cd scaffold-stark-crowd-funding
   ```

2. Install dependencies:
   ```bash
   yarn install
   ```

3. Compile the smart contract:
   ```bash
   cd packages/snfoundry/contracts
   scarb build
   ```

4. Run contract tests:
   ```bash
   scarb test
   ```

5. Deploy the contract:
   ```bash
   yarn deploy --network {NETWORK_NAME} # "sepolia" or "mainnet", defaults to "devnet"
   ```

6. Start the frontend development server:
   ```bash
   cd packages/nextjs
   yarn dev
   ```

## Smart Contract Interface

The contract implements the `IFund` interface with the following functions:

### Read Functions
* `get_fund_balance`: Get current campaign balance
* `get_fund_target`: Get campaign funding target
* `get_fund_description`: Get campaign description
* `get_deadline`: Get campaign end timestamp
* `get_token_symbol`: Get fundraising token symbol
* `get_token_address`: Get fundraising token contract address
* `get_owner`: Get contract owner address
* `get_active`: Get campaign active status

### Write Functions
* `fund_to_contract`: Contribute tokens to the campaign
* `withdraw_funds`: Withdraw funds to grantee (owner only)
* `reset_fund`: Reset campaign with new parameters (owner only)
* `set_active`: Toggle campaign active status (owner only)

## Frontend Features

### Campaign Information
* Real-time display of:
  - Campaign description
  - Current balance
  - Funding target
  - Progress percentage
  - Remaining time
  - Token symbol

### User Interface
* Wallet connection integration
* Donation input with token selection
* Progress bar visualization
* Countdown timer
* Responsive design for all devices
* Dark/Light theme support

### Owner Controls
* Campaign activation/deactivation
* Fund withdrawal management
* Campaign reset functionality

## Events

The contract emits the following events:

* `OwnableEvent`: Ownership management events
* `SelfDestructed`: Contract self-destruction event
* `Transfer`: Successful token transfer event
* `TransferFailed`: Failed transfer event
* `ResetFund`: Campaign reset event
* `ActiveChanged`: Campaign status change event

## Security Considerations

* Owner-only access control for sensitive functions
  - Withdrawal restrictions
  - Campaign state management
  - Parameter updates
* Deadline enforcement for campaign lifecycle
* Safe token transfer handling
* Input validation for all user interactions
* Proper error handling and event emission
* Role-based UI element visibility
* Transaction confirmation dialogs for important actions

## Dependencies

### Smart Contract
* OpenZeppelin Contracts (Cairo)
  - Ownable component
  - ERC20 interface

### Frontend
* Next.js 13+
* React
* Tailwind CSS
* scaffold-stark hooks
* StarkNet.js

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## demo video and Sepolia environment
demo video https://youtu.be/shciV6KVuyQ
Sepolia environment https://scaffold-stark-crowd-funding-nextjs.vercel.app/
