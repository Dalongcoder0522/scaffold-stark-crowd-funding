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
    
    // Check allowance before funding
    let initial_allowance = strk_dispatcher.allowance(DONOR(), contract_address);
    assert_eq!(initial_allowance, 0, "Initial allowance should be 0");
    
    // Approve and check allowance
    strk_dispatcher.approve(contract_address, amount);
    let after_approve_allowance = strk_dispatcher.allowance(DONOR(), contract_address);
    assert_eq!(after_approve_allowance, amount, "Allowance not set correctly");
    
    // Make donation
    dispatcher.fund_to_contract(amount);

    // Check balance and remaining allowance
    assert_eq!(dispatcher.get_fund_balance(), amount, "Wrong balance");
    let final_allowance = strk_dispatcher.allowance(DONOR(), contract_address);
    assert_eq!(final_allowance, 0, "Allowance should be 0 after transfer");
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

    // Check grantee's balance before withdrawal
    let grantee_initial_balance = strk_dispatcher.balance_of(GRANTEE());

    // Withdraw funds
    dispatcher.withdraw_funds();

    // Check contract balance is zero after withdrawal
    assert_eq!(dispatcher.get_fund_balance(), 0, "Contract balance not zero");
    
    // Check grantee received the funds
    let grantee_final_balance = strk_dispatcher.balance_of(GRANTEE());
    assert_eq!(grantee_final_balance - grantee_initial_balance, amount, "Grantee did not receive funds");
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
    let strk_dispatcher = IERC20Dispatcher { contract_address: contract_address_const::<STRK_ADDRESS>() };
    
    // First complete the current campaign
    let amount = 1000000000000000000; // 1 STRK
    strk_dispatcher.approve(contract_address, amount);
    dispatcher.fund_to_contract(amount);
    
    // Withdraw funds first
    dispatcher.withdraw_funds();
    
    // Now reset should work
    dispatcher.reset_fund(
        contract_address_const::<STRK_ADDRESS>(),
        GRANTEE(),
        2000000000000000000, // 2 STRK
        'New Campaign',
        1767222000,
        OWNER()
    );

    // Check new campaign settings
    assert_eq!(dispatcher.get_fund_target(), 2000000000000000000, "Wrong target");
    assert_eq!(dispatcher.get_fund_balance(), 0, "Not zero");
    assert_eq!(dispatcher.get_deadline(), 1767222000, "Wrong deadline");
}

#[test]
fn test_reset_fund_with_balance() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: contract_address_const::<STRK_ADDRESS>() };
    
    // Fund the contract
    let amount = 1000000000000000000; // 1 STRK
    strk_dispatcher.approve(contract_address, amount);
    dispatcher.fund_to_contract(amount);
    
    // Try to reset without withdrawing (should fail with assertion)
    dispatcher.reset_fund(
        contract_address_const::<STRK_ADDRESS>(),
        GRANTEE(),
        2000000000000000000,
        'New Campaign',
        1767222000,
        OWNER()
    );
    
    // If we get here, the test should fail
    assert(false, 'Reset should have failed');
}
