// CrowdFunding Smart Contract
//
// This contract implements a decentralized crowdfunding platform on StarkNet where:
// - Users can create and manage fundraising campaigns
// - Supporters can contribute ERC20 tokens (STRK, ETH, etc.)
// - Campaign owners can withdraw funds when conditions are met
// - Campaigns have targets, deadlines, and descriptions
//
// Security Features:
// - Ownable pattern for access control
// - Deadline enforcement
// - Active status management
// - Safe token transfer handling

use starknet::ContractAddress;

#[starknet::interface]
pub trait IFund<TContractState> {
    // Returns the current balance of tokens held by the crowdfunding contract
    fn get_fund_balance(self: @TContractState) -> u256;

    // Returns the target amount that needs to be raised for the campaign
    fn get_fund_target(self: @TContractState) -> u256;

    // Returns the campaign description stored as a felt252
    fn get_fund_description(self: @TContractState) -> felt252;

    // Returns the Unix timestamp when the campaign ends
    fn get_deadline(self: @TContractState) -> felt252;

    // Returns the symbol of the ERC20 token being used (e.g., "STRK", "ETH")
    fn get_token_symbol(self: @TContractState) -> core::byte_array::ByteArray;

    // Returns the contract address of the ERC20 token being used for fundraising
    fn get_token_address(self: @TContractState) -> ContractAddress;

    // Allows supporters to contribute tokens to the campaign
    // Requires prior approval for token transfer
    fn fund_to_contract(ref self: TContractState, amount: u256);

    // Allows the campaign owner to withdraw collected funds
    // Only succeeds if deadline is reached or target is met
    fn withdraw_funds(ref self: TContractState);

    // Resets the campaign with new parameters for another fundraising round
    // Only callable by contract owner
    fn reset_fund(ref self: TContractState,
        token: ContractAddress,          // New token contract address
        grantee_address: ContractAddress, // New beneficiary address
        fund_target: u256,               // New funding target
        fund_description: felt252,        // New campaign description
        deadline: felt252,                // New deadline timestamp
        initial_owner: ContractAddress    // New campaign owner
    );

    // Returns the address of the contract owner
    fn get_owner(self: @TContractState) -> ContractAddress;

    // Returns whether the campaign is currently active
    fn get_active(self: @TContractState) -> bool;

    // Allows owner to pause/unpause the campaign
    fn set_active(ref self: TContractState, new_active: bool);
}

#[starknet::contract]
pub mod crowdfunding {
    use starknet::ContractAddress;
    use starknet::event::EventEmitter;
    use starknet::get_caller_address;
    use openzeppelin_access::ownable::{OwnableComponent};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait};
    use core::traits::TryInto;

    // Ownable component integration
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Contract Storage Structure
    // Each field represents a critical piece of campaign information
    #[storage]
    struct Storage {
        token: ContractAddress,           // Address of ERC20 token used for fundraising
        fund_target: u256,               // Total amount needed to be raised
        grantee_address: ContractAddress, // Address that will receive the funds
        fund_description: felt252,        // Campaign details (English text)
        deadline: felt252,                // Campaign end time (Unix timestamp)
        #[substorage(v0)]
        ownable: OwnableComponent::Storage, // Access control component
        active: bool,                     // Campaign status flag
    }

    // Event Definitions
    // These events are emitted to track important contract state changes
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,  // Ownership transfer events
        SelfDestructed: SelfDestructed,         // Contract destruction event
        Transfer: Transfer,                      // Successful token transfer
        TransferFailed: TransferFailed,         // Failed token transfer
        ResetFund: ResetFund,                   // Campaign reset
        ActiveChanged: ActiveChanged,            // Status change
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

    #[derive(Drop, starknet::Event)]
    struct ActiveChanged {
        active: bool,
    }

    // Constructor: Initializes a new crowdfunding campaign
    // Sets up initial parameters and activates the campaign
    #[constructor]
    fn constructor(
        ref self: ContractState,
        token: ContractAddress,           // ERC20 token address (default: STRK)
        grantee_address: ContractAddress, // Beneficiary who receives funds
        fund_target: u256,               // Campaign goal amount
        fund_description: felt252,        // Campaign description
        deadline: felt252,                // End timestamp
        initial_owner: ContractAddress    // Campaign administrator
    ) {
        //fund token address,support any ERC20 token, if not pass token ,use STRK address 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D
        self.token.write(token);
        self.fund_target.write(fund_target);
        self.fund_description.write(fund_description);
        self.grantee_address.write(grantee_address);
        self.deadline.write(deadline);
        self.ownable.initializer(initial_owner);
        self.active.write(true);  // 初始化为激活状态
        self.emit(ResetFund{token,grantee_address,fund_target,fund_description,deadline,initial_owner});
    }

    #[abi(embed_v0)]
    impl CrowdFundingImpl of super::IFund<ContractState> {
        // Processes a new contribution to the campaign
        // Validates the transaction and transfers tokens from contributor
        fn fund_to_contract(ref self: ContractState, amount: u256) {
            //println!("amount: {}", amount);
            let caller_address = get_caller_address();
            //let caller_felt: felt252 = caller_address.try_into().unwrap();
            //println!("caller_address (hex): 0x{:x}", caller_felt);
            
            let current_contract_address = starknet::get_contract_address();
            //let contract_felt: felt252 = current_contract_address.try_into().unwrap();
            
            // Validation checks
            assert(caller_address != current_contract_address, 'No self fund.');
            assert(amount > 0, 'Amount <= 0');
            
            // Check if campaign is still active
            let current_timestamp = starknet::get_block_timestamp();
            //println!("current_timestamp: {}", current_timestamp);
            let deadline: u64 = self.deadline.read().try_into().unwrap();
            //println!("deadline: {}", deadline);
            assert(current_timestamp <= deadline, 'Campaign has ended');
            
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            //println!("contract_address (hex): 0x{:x}", contract_felt);
            
            // 检查余额
            let balance = token_dispatcher.balance_of(caller_address);
            //println!("caller balance: {}", balance);
            assert(balance >= amount, 'Insufficient balance');
            
            // 检查授权额度
            let allowance = token_dispatcher.allowance(caller_address, current_contract_address);
            //println!("allowance: {}", allowance);
            assert(allowance >= amount, 'Insufficient allowance');
            
            // 执行转账
            //println!("Attempting transfer from 0x{:x} to 0x{:x} amount {}", 
            //    caller_felt,
            //    contract_felt,
            //    amount
            //);
            
            // Check allowance before transfer
            //let allowance = token_dispatcher.allowance(caller_address, current_contract_address);
            //println!("Contract allowance: {}", allowance);
            
            match token_dispatcher.transfer_from(
                caller_address, current_contract_address, amount
            ) {
                true => {
                    //println!("Transfer successful!");
                    self.emit(Transfer { from: caller_address, to: current_contract_address, amount: amount });
                },
                false => {
                    //println!("Transfer failed!");
                    self.emit(TransferFailed {
                        from: caller_address,
                        to: current_contract_address,
                        amount: amount,
                        error_message: 'Failed to transfer!'
                    });
                }
            }
        }

        // Processes withdrawal of funds to the grantee
        // Checks campaign conditions and transfers total balance
        fn withdraw_funds(ref self: ContractState) {
            self.ownable.assert_only_owner();
            assert(self.active.read(), 'Not active status');
            //println!("in:in" );
            // Check if deadline has passed or target is met
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            let current_timestamp = starknet::get_block_timestamp();
            let deadline: u64 = self.deadline.read().try_into().unwrap();
            let current_contract_address = starknet::get_contract_address();
            let balance = token_dispatcher.balance_of(current_contract_address);
            let target = self.fund_target.read();
            
            //println!("current_timestamp: {}", current_timestamp);
            //println!("deadline: {}", deadline);
            //println!("fund_target raw: {}", target);
            //println!("fund_target from getter: {}", self.get_fund_target());
            //println!("balance: {}", balance);

            assert(
                current_timestamp > deadline || balance >= target,
                'Cannot withdraw!'
            );

            //println!("Assert passed successfully");
            let grantee_address = self.grantee_address.read();
            //let grantee_address_felt: felt252 = grantee_address.try_into().unwrap();
            
            //println!("Attempting transfer_from...");
            //println!("From address: (hex): 0x{:x}", contract_felt);
            //println!("To address: (hex): 0x{:x}", grantee_address_felt);
            //println!("Amount: {}", balance);
            
            //println!("Attempting direct transfer...");
            match token_dispatcher.transfer(grantee_address, balance) {
                true => {
                    //println!("Transfer successful!");
                    self.active.write(false);  // 提现后设置为非激活状态
                    self.emit(Transfer { from: current_contract_address, to: grantee_address, amount: balance });
                    self.emit(ActiveChanged { active: false });
                },
                false => {
                    //println!("Transfer failed!");
                    self.emit(TransferFailed {
                        from: current_contract_address,
                        to: grantee_address,
                        amount: balance,
                        error_message: 'Failed to withdraw!'
                    });
                }
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

        fn get_token_symbol(self: @ContractState) -> core::byte_array::ByteArray {
            let token_address = self.token.read();
            let contract_felt: felt252 = token_address.try_into().unwrap();
            //println!("Token address: (hex): 0x{:x}", contract_felt);

            // 根据合约地址返回对应的符号
            if contract_felt == 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D {
                //println!("Token identified as STRK");
                let strk: core::byte_array::ByteArray = "STRK";
                strk
            } else if contract_felt == 0x049D36570D4e46f48e99674bd3fcc84644DdD6b96F7C741B1562B82f9e004dC7 {
                //println!("Token identified as ETH");
                let eth: core::byte_array::ByteArray = "ETH";
                eth
            } else {
                IERC20MetadataDispatcher { contract_address: self.token.read() }.symbol()
            }
        }

        // Returns the token address
        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.token.read()
        }
        
        // Returns the contract owner
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }

        // 获取活动状态
        fn get_active(self: @ContractState) -> bool {
            self.active.read()
        }

        // 设置活动状态（只有所有者可以调用）
        fn set_active(ref self: ContractState, new_active: bool) {
            self.ownable.assert_only_owner();
            self.active.write(new_active);
            self.emit(ActiveChanged { active: new_active });
        }

        //Reset the contract and start a new crowdfunding
        fn reset_fund(ref self: ContractState,
            token: ContractAddress,          // New token contract address
            grantee_address: ContractAddress, // New beneficiary address
            fund_target: u256,               // New funding target
            fund_description: felt252,        // New campaign description
            deadline: felt252,                // New deadline timestamp
            initial_owner: ContractAddress    // New campaign owner
        ) {
            self.ownable.assert_only_owner();
            // Reset contract after withdraw
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            let current_contract_address = starknet::get_contract_address();
            let balance = token_dispatcher.balance_of(current_contract_address);
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
            self.active.write(true);  // 重置后设置为激活状态
            self.emit(ResetFund{token:self.token.read(),grantee_address,fund_target,fund_description,deadline,initial_owner});
            self.emit(ActiveChanged { active: true });
        }
    }
}
