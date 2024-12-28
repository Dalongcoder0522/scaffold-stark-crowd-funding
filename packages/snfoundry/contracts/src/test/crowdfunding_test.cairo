use super::super::crowdfunding::{IFundDispatcher, IFundDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknet::{ContractAddress, contract_address_const};

// Test addresses
fn OWNER() -> ContractAddress {
    contract_address_const::<0x02dA5254690b46B9C4059C25366D1778839BE63C142d899F0306fd5c312A5918>()
}

fn GRANTEE() -> ContractAddress {
    contract_address_const::<0x03dA5254690b46B9C4059C25366D1778839BE63C142d899F0306fd5c312A5919>()
}

fn DONOR() -> ContractAddress {
    contract_address_const::<0x04dA5254690b46B9C4059C25366D1778839BE63C142d899F0306fd5c312A5920>()
}

// STRK token address on Sepolia
const STRK_ADDRESS: felt252 = 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D;

// Helper function to deploy the contract
fn deploy_crowdfunding() -> ContractAddress {
    let contract_class = declare("crowdfunding").unwrap().contract_class();
    let mut calldata = array![];
    // Add constructor arguments
    calldata.append_serde(contract_address_const::<STRK_ADDRESS>()); // token
    calldata.append_serde(GRANTEE()); // grantee_address
    calldata.append_serde(1000000000000000000); // fund_target (1 STRK)
    calldata.append_serde('Test Campaign'); // fund_description
    calldata.append_serde(1735686000); // deadline (Dec 31, 2024)
    calldata.append_serde(OWNER()); // initial_owner
    
    let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
    contract_address
}

#[test]
fn test_contract_initialization() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };

    // Check initial state
    assert_eq!(dispatcher.get_fund_target(), 1000000000000000000, "Wrong target");
    assert_eq!(dispatcher.get_fund_balance(), 0, "Wrong balance");
    assert_eq!(dispatcher.get_deadline(), 1735686000, "Wrong deadline");
}

#[test]
fn test_fund_to_contract() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: contract_address_const::<STRK_ADDRESS>() };
    
    // Setup donor with STRK tokens and make donation
    let amount = 500000000000000000; // 0.5 STRK
    strk_dispatcher.approve(contract_address, amount);
    dispatcher.fund_to_contract(amount);

    // Check balance
    assert_eq!(dispatcher.get_fund_balance(), amount, "Wrong balance");
}

#[test]
fn test_withdraw_funds() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: contract_address_const::<STRK_ADDRESS>() };
    
    // Fund the contract first
    let amount = 1000000000000000000; // 1 STRK (meets target)
    strk_dispatcher.approve(contract_address, amount);
    dispatcher.fund_to_contract(amount);

    // Withdraw funds
    dispatcher.withdraw_funds();

    // Check balance is zero after withdrawal
    assert_eq!(dispatcher.get_fund_balance(), 0, "Not zero");
}

#[test]
fn test_withdraw_before_target() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    
    // Fund with amount less than target
    let amount = 500000000000000000; // 0.5 STRK
    let strk_dispatcher = IERC20Dispatcher { contract_address: contract_address_const::<STRK_ADDRESS>() };
    strk_dispatcher.approve(contract_address, amount);
    dispatcher.fund_to_contract(amount);

    // Check initial balance
    let initial_balance = dispatcher.get_fund_balance();
    assert_eq!(initial_balance, amount, "Initial balance wrong");

    // Try to withdraw (should fail)
    dispatcher.withdraw_funds();

    // Balance should remain unchanged since withdrawal should fail
    let final_balance = dispatcher.get_fund_balance();
    assert_eq!(final_balance, initial_balance, "Balance should not change");
}

#[test]
fn test_reset_fund() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    
    // First complete the current campaign
    let amount = 1000000000000000000; // 1 STRK
    let strk_dispatcher = IERC20Dispatcher { contract_address: contract_address_const::<STRK_ADDRESS>() };
    strk_dispatcher.approve(contract_address, amount);
    dispatcher.fund_to_contract(amount);
    dispatcher.withdraw_funds();

    // Reset for new campaign
    dispatcher.reset_fund(
        contract_address_const::<STRK_ADDRESS>(),
        GRANTEE(),
        2000000000000000000, // 2 STRK
        'New Campaign',
        1767222000, // New deadline
        OWNER()
    );

    // Check new campaign settings
    assert_eq!(dispatcher.get_fund_target(), 2000000000000000000, "Wrong target");
    assert_eq!(dispatcher.get_fund_balance(), 0, "Not zero");
    assert_eq!(dispatcher.get_deadline(), 1767222000, "Wrong deadline");
}
