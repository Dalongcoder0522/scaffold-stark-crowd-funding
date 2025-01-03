use super::super::crowdfunding::{IFundDispatcher, IFundDispatcherTrait};
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

// Helper function to deploy the contract
fn deploy_crowdfunding() -> ContractAddress {
    let contract_class = declare("crowdfunding").unwrap().contract_class();
    let mut calldata = array![];
    // Add constructor arguments
    calldata.append_serde(OWNER()); // token (using owner address as mock token)
    calldata.append_serde(GRANTEE()); // grantee_address
    calldata.append_serde(1000000000000000000_u256); // fund_target (1 TOKEN)
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
    assert_eq!(dispatcher.get_fund_target(), 1000000000000000000_u256, "Wrong target");
    assert_eq!(dispatcher.get_fund_balance(), 0_u256, "Wrong balance");
    assert_eq!(dispatcher.get_deadline(), 1735686000, "Wrong deadline");
    assert_eq!(dispatcher.get_active(), true, "Should be active");
}

#[test]
fn test_fund_to_contract() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    
    // Make donation
    let amount = 500000000000000000_u256; // 0.5 TOKEN
    dispatcher.fund_to_contract(amount);

    // Check balance
    assert_eq!(dispatcher.get_fund_balance(), amount, "Wrong balance after funding");
}

#[test]
fn test_withdraw_funds() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    
    // Fund the contract first
    let amount = 1000000000000000000_u256; // 1 TOKEN (meets target)
    dispatcher.fund_to_contract(amount);

    // Withdraw funds
    dispatcher.withdraw_funds();

    // Check contract state after withdrawal
    assert_eq!(dispatcher.get_fund_balance(), 0_u256, "Balance should be zero");
    assert_eq!(dispatcher.get_active(), false, "Should be inactive");
}

#[test]
fn test_reset_fund() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    
    // First complete the current campaign
    let amount = 1000000000000000000_u256; // 1 TOKEN
    dispatcher.fund_to_contract(amount);
    dispatcher.withdraw_funds();
    
    // Now reset campaign
    dispatcher.reset_fund(
        OWNER(), // Using owner address as mock token
        GRANTEE(),
        2000000000000000000_u256, // 2 TOKEN
        'New Campaign',
        1767222000,
        OWNER()
    );

    // Check new campaign settings
    assert_eq!(dispatcher.get_fund_target(), 2000000000000000000_u256, "Wrong target");
    assert_eq!(dispatcher.get_fund_balance(), 0_u256, "Not zero");
    assert_eq!(dispatcher.get_deadline(), 1767222000, "Wrong deadline");
    assert_eq!(dispatcher.get_active(), true, "Should be active");
}

#[test]
fn test_set_active() {
    let contract_address = deploy_crowdfunding();
    let dispatcher = IFundDispatcher { contract_address };
    
    // Initially active
    assert_eq!(dispatcher.get_active(), true, "Should start active");
    
    // Deactivate
    dispatcher.set_active(false);
    assert_eq!(dispatcher.get_active(), false, "Should be inactive");
    
    // Reactivate
    dispatcher.set_active(true);
    assert_eq!(dispatcher.get_active(), true, "Should be active again");
}
