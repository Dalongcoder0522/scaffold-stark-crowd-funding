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

    // Returns the token symbol
    fn get_token_symbol(self: @TContractState) -> core::byte_array::ByteArray;

    // Returns the token address
    fn get_token_address(self: @TContractState) -> ContractAddress;

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

    // Returns the contract owner
    fn get_owner(self: @TContractState) -> ContractAddress;

    // 获取活动状态
    fn get_active(self: @TContractState) -> bool;

    // 设置活动状态（只有所有者可以调用）
    fn set_active(ref self: TContractState, new_active: bool);
}


#[starknet::contract]
pub mod crowdfunding {
    use starknet::ContractAddress;
    use starknet::event::EventEmitter;
    use starknet::get_caller_address;
    use openzeppelin::access::ownable::{OwnableComponent};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait};
    use core::traits::TryInto;

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
        active: bool,               // Campaign active status
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
        ActiveChanged: ActiveChanged,
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
        self.active.write(true);  // 初始化为激活状态
        self.emit(ResetFund{token,grantee_address,fund_target,fund_description,deadline,initial_owner});
    }

    #[abi(embed_v0)]
    impl CrowdFundingImpl of super::IFund<ContractState> {
        // Allows users to donate STRK tokens to the contract
        fn fund_to_contract(ref self: ContractState, amount: u256) {
            println!("amount: {}", amount);
            let caller_address = get_caller_address();
            let caller_felt: felt252 = caller_address.try_into().unwrap();
            println!("caller_address (hex): 0x{:x}", caller_felt);
            
            let current_contract_address = starknet::get_contract_address();
            let contract_felt: felt252 = current_contract_address.try_into().unwrap();
            
            // Validation checks
            assert(caller_address != current_contract_address, 'No self fund.');
            assert(amount > 0, 'Amount <= 0');
            
            // Check if campaign is still active
            let current_timestamp = starknet::get_block_timestamp();
            println!("current_timestamp: {}", current_timestamp);
            let deadline: u64 = self.deadline.read().try_into().unwrap();
            println!("deadline: {}", deadline);
            assert(current_timestamp <= deadline, 'Campaign has ended');
            
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            println!("contract_address (hex): 0x{:x}", contract_felt);
            
            // 检查余额
            let balance = token_dispatcher.balance_of(caller_address);
            println!("caller balance: {}", balance);
            assert(balance >= amount, 'Insufficient balance');
            
            // 检查授权额度
            let allowance = token_dispatcher.allowance(caller_address, current_contract_address);
            println!("allowance: {}", allowance);
            assert(allowance >= amount, 'Insufficient allowance');
            
            // 执行转账
            println!("Attempting transfer from 0x{:x} to 0x{:x} amount {}", 
                caller_felt,
                contract_felt,
                amount
            );
            
            // Check allowance before transfer
            let allowance = token_dispatcher.allowance(caller_address, current_contract_address);
            println!("Contract allowance: {}", allowance);
            
            match token_dispatcher.transfer_from(
                caller_address, current_contract_address, amount
            ) {
                true => {
                    println!("Transfer successful!");
                    self.emit(Transfer { from: caller_address, to: current_contract_address, amount: amount });
                },
                false => {
                    println!("Transfer failed!");
                    self.emit(TransferFailed {
                        from: caller_address,
                        to: current_contract_address,
                        amount: amount,
                        error_message: 'Failed to transfer!'
                    });
                }
            }
        }

        // Withdraws funds to grantee
        // Can only be called by contract owner when deadline is reached or target is met
        fn withdraw_funds(ref self: ContractState) {
            self.ownable.assert_only_owner();
            assert(self.active.read(), 'Not active status');
            println!("in:in" );
            // Check if deadline has passed or target is met
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token.read() };
            let current_timestamp = starknet::get_block_timestamp();
            let deadline: u64 = self.deadline.read().try_into().unwrap();
            let current_contract_address = starknet::get_contract_address();
            let balance = token_dispatcher.balance_of(current_contract_address);
            let target = self.fund_target.read();
            
            println!("current_timestamp: {}", current_timestamp);
            println!("deadline: {}", deadline);
            println!("fund_target raw: {}", target);
            println!("fund_target from getter: {}", self.get_fund_target());
            println!("balance: {}", balance);

            assert(
                current_timestamp > deadline || balance >= target,
                'Cannot withdraw!'
            );

            println!("Assert passed successfully");
            let contract_felt: felt252 = current_contract_address.try_into().unwrap();
            let grantee_address = self.grantee_address.read();
            let grantee_address_felt: felt252 = grantee_address.try_into().unwrap();
            
            println!("Attempting transfer_from...");
            println!("From address: (hex): 0x{:x}", contract_felt);
            println!("To address: (hex): 0x{:x}", grantee_address_felt);
            println!("Amount: {}", balance);
            
            println!("Attempting direct transfer...");
            match token_dispatcher.transfer(grantee_address, balance) {
                true => {
                    println!("Transfer successful!");
                    self.active.write(false);  // 提现后设置为非激活状态
                    self.emit(Transfer { from: current_contract_address, to: grantee_address, amount: balance });
                    self.emit(ActiveChanged { active: false });
                },
                false => {
                    println!("Transfer failed!");
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
            println!("Token address: (hex): 0x{:x}", contract_felt);

            // 根据合约地址返回对应的符号
            if contract_felt == 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D {
                println!("Token identified as STRK");
                let strk: core::byte_array::ByteArray = "STRK";
                strk
            } else if contract_felt == 0x049D36570D4e46f48e99674bd3fcc84644DdD6b96F7C741B1562B82f9e004dC7 {
                println!("Token identified as ETH");
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
            token: ContractAddress,
            grantee_address: ContractAddress,
            fund_target: u256,
            fund_description: felt252,
            deadline: felt252,
            initial_owner: ContractAddress
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
