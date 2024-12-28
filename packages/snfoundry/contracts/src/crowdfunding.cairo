// CrowdFunding Contract
// This contract implements a crowdfunding mechanism where users can:
// 1. Fund the contract with STRK tokens
// 2. Withdraw funds to a grantee address when target is met or deadline is reached
use starknet::ContractAddress;
#[starknet::interface]
pub trait IFund<TContractState> {
    // Returns the current balance of the crowdfunding contract
    fn get_fund_balance(self: @TContractState) -> u256;

    // Returns the funding target amount
    fn get_fund_target(self: @TContractState) -> u256;

    // Returns the description of the crowdfunding campaign
    fn get_fund_description(self: @TContractState) -> felt252;

    // Returns the campaign deadline timestamp
    fn get_deadline(self: @TContractState) -> felt252;

    // Allows users to fund the contract with STRK tokens
    fn fund_to_contract(ref self: TContractState, amount: u256);

    // Withdraws all funds to the grantee
    fn withdraw_funds(ref self: TContractState);

    // reset funding for another patron
    fn reset_fund(ref self: TContractState,
        token: ContractAddress,
        grantee_address: ContractAddress,
        fund_target: u256,
        fund_description: felt252,
        deadline: felt252,
        initial_owner: ContractAddress);
}


#[starknet::contract]
pub mod crowdfunding {
    use starknet::ContractAddress;
    use starknet::event::EventEmitter;
    use starknet::get_caller_address;
    use openzeppelin_access::ownable::{OwnableComponent};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    // Ownable component integration
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Contract storage structure
    #[storage]
    struct Storage {
        token: ContractAddress,     //fund token address
        fund_target: u256,           // Target amount to raise
        grantee_address: ContractAddress, // Beneficiary address
        fund_description: felt252,     // Campaign description (English only)
        deadline: felt252,              // Campaign end timestamp Unix timestamp 1740805200(2025年3月1日00:00:00) https://tool.chinaz.com/tools/unixtime.aspx
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    // Event definitions
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        SelfDestructed: SelfDestructed,
        Transfer: Transfer,
        TransferFailed: TransferFailed,
        ResetFund: ResetFund,
    }

    #[derive(Drop, starknet::Event)]
    struct SelfDestructed {
        recipient: ContractAddress, // Address receiving the remaining funds
        amount: u256,            // Remaining funds
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferFailed {
        from: ContractAddress,
        to: ContractAddress,
        amount: u256,
        error_message: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct ResetFund {
        token: ContractAddress,
        grantee_address: ContractAddress,
        fund_target: u256,
        fund_description: felt252,
        deadline: felt252,
        initial_owner: ContractAddress
    }

    // Contract constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        token: ContractAddress,
        grantee_address: ContractAddress,
        fund_target: u256,
        fund_description: felt252,
        deadline: felt252,
        initial_owner: ContractAddress
    ) {
        //fund token address,support any ERC20 token, if not pass token ,use STRK address 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D
        self.token.write(token);
        self.fund_target.write(fund_target);
        self.fund_description.write(fund_description);
        self.grantee_address.write(grantee_address);
        self.deadline.write(deadline);
        self.ownable.initializer(initial_owner);
        self.emit(ResetFund{token,grantee_address,fund_target,fund_description,deadline,initial_owner});
    }

    #[abi(embed_v0)]
    impl CrowdFundingImpl of super::IFund<ContractState> {
        // Allows users to donate STRK tokens to the contract
        fn fund_to_contract(ref self: ContractState, amount: u256) {
            let caller_address = get_caller_address();
            let current_contract_address = starknet::get_contract_address();
            
            // Validation checks
            assert(caller_address != current_contract_address, 'No self fund.');
            assert(amount > 0, 'Amount <= 0');
            
            // Check if campaign is still active
            let current_timestamp = starknet::get_block_timestamp();
            let deadline: u64 = self.deadline.read().try_into().unwrap();
            assert(current_timestamp <= deadline, 'Campaign has ended');
            
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            let caller_address = starknet::get_caller_address();

            let transfer_successful = token_dispatcher.transfer_from(
                caller_address, current_contract_address, amount
            );

            if transfer_successful {
                self.emit(Transfer { from: caller_address,to: current_contract_address, amount: amount });
            } else {
                self.emit(TransferFailed {
                    from: caller_address,
                    to: current_contract_address,
                    amount: amount,
                    error_message: 'Failed to transfer!'
                });
            }
        }

        // Withdraws funds to grantee
        // Can only be called by contract owner when deadline is reached or target is met
        fn withdraw_funds(ref self: ContractState) {
            self.ownable.assert_only_owner();
            
            // Check if deadline has passed or target is met
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            let current_timestamp = starknet::get_block_timestamp();
            let deadline: u64 = self.deadline.read().try_into().unwrap();
            let current_contract_address = starknet::get_contract_address();
            let balance = token_dispatcher.balance_of(current_contract_address);
            assert(
                current_timestamp > deadline || balance >= self.fund_target.read(),
                'Cannot withdraw!'
            );
            let grantee_address = self.grantee_address.read();
            let transfer_successful = token_dispatcher.transfer_from(
                current_contract_address, grantee_address, balance
            );
        
            if transfer_successful {
                self.emit(Transfer { from: current_contract_address, to: grantee_address, amount: balance });
            } else {
                self.emit(TransferFailed {
                    from: current_contract_address,
                    to: grantee_address,
                    amount: balance,
                    error_message: 'Failed to withdraw!'
                });
            }
        }

        // Returns the current contract balance
        fn get_fund_balance(self: @ContractState) -> u256 {
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            let current_contract_address = starknet::get_contract_address();
            let balance = token_dispatcher.balance_of(current_contract_address);
            return balance;
        }

        // Returns the funding target amount
        fn get_fund_target(self: @ContractState) -> u256 {
            self.fund_target.read()
        }

        // Returns the crowdfunding campaign description
        fn get_fund_description(self: @ContractState) -> felt252 {
            self.fund_description.read()
        }

        // Returns the campaign deadline timestamp
        fn get_deadline(self: @ContractState) -> felt252 {
            self.deadline.read()
        }
        
        //Reset the contract and start a new crowdfunding
        fn reset_fund(ref self: ContractState,
            token: ContractAddress,
            grantee_address: ContractAddress,
            fund_target: u256,
            fund_description: felt252,
            deadline: felt252,
            initial_owner: ContractAddress
        ) {
            self.ownable.assert_only_owner();
            // Check if deadline has passed or target is met
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            let current_timestamp = starknet::get_block_timestamp();
            let deadline_u64: u64 = self.deadline.read().try_into().unwrap();
            let current_contract_address = starknet::get_contract_address();
            let balance = token_dispatcher.balance_of(current_contract_address);
            assert(
                current_timestamp > deadline_u64 || balance >= self.fund_target.read(),
                'Cannot reset!'
            );
            assert(
                balance <= 0,
                'Please withdraw first!'
            );
            self.token.write(token);
            self.fund_target.write(fund_target);
            self.fund_description.write(fund_description);
            self.grantee_address.write(grantee_address);
            self.deadline.write(deadline);
            self.ownable.initializer(initial_owner);
            self.emit(ResetFund{token:self.token.read(),grantee_address,fund_target,fund_description,deadline,initial_owner});
        }
    }
}
