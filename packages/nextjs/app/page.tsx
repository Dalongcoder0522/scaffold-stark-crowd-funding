/**
 * Starknet Crowdfunding Frontend
 * 
 * This is the main page component for the crowdfunding dApp.
 * It provides a user interface for:
 * - Viewing campaign details and progress
 * - Making donations in ERC20 tokens(Current UI only supports STRK and ETH)
 * - Managing campaign status (for owners)
 * - Withdrawing funds (for owners)
 * 
 * The component integrates with Starknet smart contracts using scaffold-stark hooks
 * and handles all necessary token approvals and transactions.
 */

'use client';

import { ConnectedAddress } from "~~/components/ConnectedAddress";
import { InputBase } from "~~/components/scaffold-stark";
import { useState, useMemo, useEffect } from "react";
import { useScaffoldReadContract, useScaffoldWriteContract, useDeployedContractInfo } from "~~/hooks/scaffold-stark";
import { useAccount } from "~~/hooks/useAccount";

/**
 * Utility function to convert felt252 to readable string
 * @param felt - The felt252 value to convert
 * @returns Decoded string from the felt252 value
 */
const feltToString = (felt: string) => {
  const hex = BigInt(felt).toString(16);
  const paddedHex = hex.length % 2 ? '0' + hex : hex;
  const bytes = [];
  for (let i = 0; i < paddedHex.length; i += 2) {
    bytes.push(parseInt(paddedHex.slice(i, i + 2), 16));
  }
  return new TextDecoder().decode(new Uint8Array(bytes));
};

/**
 * Formats token amounts with proper decimal places
 * @param amount - The amount to format (in wei)
 * @param decimals - Number of decimal places (default: 18 for most ERC20 tokens)
 * @returns Formatted string with appropriate decimal places
 */
const formatSTRK = (amount: string | undefined, decimals: number = 18): string => {
  if (!amount) return "0";
  const value = BigInt(amount);
  const divisor = BigInt(10 ** decimals);
  const integerPart = value / divisor;
  const fractionalPart = value % divisor;
  
  // 处理小数部分，去掉末尾的0
  let fractionalStr = fractionalPart.toString().padStart(decimals, '0');
  while (fractionalStr.endsWith('0') && fractionalStr.length > 0) {
    fractionalStr = fractionalStr.slice(0, -1);
  }
  
  return fractionalStr.length > 0 
    ? `${integerPart}.${fractionalStr}`
    : integerPart.toString();
};

/**
 * Formats remaining time into human-readable countdown
 * @param remainingTime - Time remaining in seconds
 * @returns Formatted string showing days, hours, minutes, and seconds
 */
const formatCountdown = (remainingTime: number): string => {
  if (remainingTime <= 0) return "Ended";
  
  const days = Math.floor(remainingTime / (24 * 60 * 60));
  const hours = Math.floor((remainingTime % (24 * 60 * 60)) / (60 * 60));
  const minutes = Math.floor((remainingTime % (60 * 60)) / 60);
  const seconds = Math.floor(remainingTime % 60);

  if (days > 0) {
    return `${days}d ${hours}h ${minutes}m ${seconds}s`;
  } else if (hours > 0) {
    return `${hours}h ${minutes}m ${seconds}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${seconds}s`;
  } else {
    return `${seconds}s`;
  }
};

/**
 * Format deadline timestamp to human readable date and time
 * @param timestamp Unix timestamp in seconds
 * @returns Formatted date string
 */
const formatDeadline = (timestamp: string) => {
  if (!timestamp) return "Loading...";
  const date = new Date(Number(timestamp) * 1000);
  return date.toLocaleDateString() + " " + date.toLocaleTimeString();
};

/**
 * Main component for the crowdfunding page
 * Manages campaign state, user interactions, and UI rendering
 */
const Home = () => {
  // Form and UI state management
  const [sendValue, setSendValue] = useState("");           // Donation amount input
  const [isLoading, setIsLoading] = useState(false);        // Loading state for transactions
  const [error, setError] = useState<string | null>(null);  // Error message display
  const [pendingAmount, setPendingAmount] = useState<bigint | null>(null);  // Amount pending confirmation
  const [showConfirmDialog, setShowConfirmDialog] = useState(false);        // Confirmation dialog visibility
  const [remainingTime, setRemainingTime] = useState<number>(0);           // Campaign time remaining
  
  // User account state
  const { address } = useAccount();  // Connected wallet address

  // Contract state queries using scaffold-stark hooks
  const { data: crowdfundingContract } = useDeployedContractInfo("crowdfunding");
  const { data: fundDescription, isLoading: isLoadingDescription } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_fund_description",
  });

  const { data: tokenSymbol, isLoading: isLoadingSymbol } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_token_symbol",
  });

  // Memoized token contract name
  const tokenContractName = useMemo(() => {
    if (!tokenSymbol) return "Strk"; // Default to STRK
    const symbol = tokenSymbol.toString().toUpperCase();
    if (symbol === "ETH") return "Eth";
    if (symbol === "STRK") return "Strk";
    return "Strk";
  }, [tokenSymbol]) as "Eth" | "Strk";

  const { data: fundBalance, isLoading: isLoadingBalance } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_fund_balance",
  });

  const { data: fundTarget, isLoading: isLoadingTarget } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_fund_target",
  });

  const { data: deadline } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_deadline",
  });

  const { data: initialOwner } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_owner",
  });

  const { data: isActive } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_active",
  });

  // Contract write functions
  const { sendAsync: approveToken, isPending: isApproving } = useScaffoldWriteContract({
    contractName: tokenContractName,
    functionName: "approve",
    args: [crowdfundingContract?.address, 0n] as const
  });

  const { sendAsync: fundToContract, isPending: isWriteLoading } = useScaffoldWriteContract({
    contractName: "crowdfunding",
    functionName: "fund_to_contract",
    args: [0n] as const
  });

  const { sendAsync: withdrawFunds, isPending: isWithdrawing } = useScaffoldWriteContract({
    contractName: "crowdfunding",
    functionName: "withdraw_funds",
  });

  const { sendAsync: setActive, isPending: isSettingActive } = useScaffoldWriteContract({
    contractName: "crowdfunding",
    functionName: "set_active",
    args: [true] as const
  });

  // Memoized computations
  const isOwner = useMemo(() => {
    if (!initialOwner || !address) return false;
    const ownerHex = "0x" + BigInt(initialOwner.toString()).toString(16).padStart(64, '0');
    const addressHex = address.toLowerCase();
    return ownerHex.toLowerCase() === addressHex;
  }, [initialOwner, address]);

  // Transaction handlers
  const handleToggleActive = async () => {
    // Toggle campaign active status
    try {
      setError(null);
      setIsLoading(true);

      console.log("Toggling active status...");
      const newStatus = !isActive;
      const txHash = await setActive({ args: [newStatus] });
      if (txHash) {
        console.log(`Status change transaction submitted: ${newStatus ? "activated" : "deactivated"}`);
      }
    } catch (error) {
      console.error("Error changing status:", error);
      setError(error instanceof Error ? error.message : "Failed to change status");
    } finally {
      setIsLoading(false);
    }
  };

  const handleDonate = async () => {
    // Handle donation flow including validation and token approval
    try {
      setError(null);
      setIsLoading(true);
      
      // 输入验证
      if (!sendValue) {
        setError("Please enter an amount");
        return;
      }

      // 检查钱包连接
      if (!address) {
        setError("Please connect your wallet first");
        return;
      }

      // 检查合约地址
      if (!crowdfundingContract?.address) {
        setError("Contract not deployed");
        return;
      }

      // 数值验证
      const parsedAmount = BigInt(sendValue);
      if (parsedAmount <= 0n) {
        setError("Amount must be greater than 0");
        return;
      }

      // 转换为完整的 STRK (乘以 10^18)
      const amount = parsedAmount * 10n ** 18n;
      console.log("Converting to STRK:", {
        input: sendValue,
        converted: amount.toString()
      });

      // 这里modal dialog提示用户确认捐赠金额
      if (fundTarget) {
        setPendingAmount(amount);
        setShowConfirmDialog(true);
        return;
      }

      // 先调用 approve
      console.log("Approving token...");
      try {
        const approveTx = await approveToken({
          args: [crowdfundingContract.address, amount]
        });
        if (!approveTx) {
          setError("Failed to approve token");
          return;
        }
        console.log("Token approved:", approveTx);

        // 然后调用 fund_to_contract
        console.log("Donating...");
        const txHash = await fundToContract({ args: [amount] });
        if (txHash) {
          console.log("Transaction submitted:", txHash);
          setSendValue("");
        }
      } catch (error) {
        console.error("Error in transaction:", error);
        setError(error instanceof Error ? error.message : "Transaction failed");
      }
    } catch (error) {
      console.error("Error donating:", error);
      if (error instanceof Error && error.message.includes("invalid number")) {
        setError("Please enter a valid number");
      } else {
        setError(error instanceof Error ? error.message : "Failed to donate");
      }
    } finally {
      setIsLoading(false);
    }
  };

  const handleWithdraw = async () => {
    // Process withdrawal for contract owner
    try {
      setError(null);
      setIsLoading(true);

      console.log("Withdrawing funds...");
      const txHash = await withdrawFunds();
      if (txHash) {
        console.log("Withdrawal transaction submitted:", txHash);
      }
    } catch (error) {
      console.error("Error withdrawing:", error);
      setError(error instanceof Error ? error.message : "Failed to withdraw");
    } finally {
      setIsLoading(false);
    }
  };

  const handleCancel = () => {
    setShowConfirmDialog(false);
    setPendingAmount(null);
    setIsLoading(false);
  };

  const handleConfirmDonate = async () => {
    // Confirm donation and execute transaction
    try {
      if (!pendingAmount) return;
      
      setShowConfirmDialog(false);
      const amount = pendingAmount;
      setPendingAmount(null);

      // 先调用 approve
      console.log("Approving token...");
      try {
        const approveTx = await approveToken({
          args: [crowdfundingContract?.address, amount]
        });
        if (!approveTx) {
          setError("Failed to approve token");
          return;
        }
        console.log("Token approved:", approveTx);

        // 然后调用 fund_to_contract
        console.log("Donating...");
        const txHash = await fundToContract({ args: [amount] });
        if (txHash) {
          console.log("Transaction submitted:", txHash);
          setSendValue("");
        }
      } catch (error) {
        console.error("Error in transaction:", error);
        setError(error instanceof Error ? error.message : "Transaction failed");
      }
    } catch (error) {
      console.error("Error in confirmation:", error);
      setError(error instanceof Error ? error.message : "Confirmation failed");
    } finally {
      setIsLoading(false);
    }
  };

  // Countdown timer effect
  useEffect(() => {
    // Update remaining time every second
    if (!deadline) return;

    const updateCountdown = () => {
      const now = Math.floor(Date.now() / 1000);
      const endTime = Number(deadline.toString());
      const timeLeft = endTime - now;
      setRemainingTime(Math.max(0, timeLeft));
    };

    // 初始更新
    updateCountdown();

    // 每秒更新一次
    const timer = setInterval(updateCountdown, 1000);

    return () => clearInterval(timer);
  }, [deadline]);

  // UI Rendering
  return (
    <div className="bg-gradient-to-b from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
      {/* Main layout container with responsive padding */}
      <div className="flex flex-col">
        {/* Hero Section - Top */}
        <div className="flex-shrink-0 px-4 sm:px-6 lg:px-8 py-6">
          <div className="text-center">
            <h1 className="text-3xl sm:text-4xl font-extrabold text-gray-900 dark:text-white">
              <span className="block text-indigo-600 dark:text-indigo-400">Starknet CrowdFunding</span>
              <span className="block">{fundDescription ? feltToString(fundDescription.toString()) : "Loading..."}</span>
            </h1>
            <div className="mt-2 text-base text-gray-500 dark:text-gray-400 sm:text-lg">
              Join us in making a difference. Support this project with {tokenSymbol ? tokenSymbol.toString().toUpperCase() : "STRK"}.
            </div>
          </div>

          {/* Wallet Connection */}
          <div className="mt-4 flex justify-center">
            <ConnectedAddress />
          </div>

          {isOwner && (
            <div className="mt-2 text-center">
              <div className="text-sm text-gray-500 dark:text-gray-400">
                You are the contract owner
              </div>
            </div>
          )}
        </div>

        {/* Main Content */}
        <div className="px-4 sm:px-6 lg:px-8 pb-6">
          {isActive ? (
            <div className="max-w-4xl mx-auto">
              {isLoadingDescription || isLoadingBalance || isLoadingTarget || isLoadingSymbol ? (
                <div className="flex justify-center items-center">
                  <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-indigo-500"></div>
                </div>
              ) : (
                <div className="bg-white dark:bg-gray-800 shadow overflow-hidden rounded-lg">
                  {/* Progress Card */}
                  <div className="p-4">
                    <div className="space-y-4">
                      {/* Progress Bar */}
                      <div>
                        <div className="flex justify-between mb-2 text-sm font-medium text-gray-700 dark:text-gray-300">
                          <span>Progress: {fundBalance && fundTarget ? (Number(fundBalance.toString()) / Number(fundTarget.toString())) * 100 : 0}%</span>
                          <span>Target: {formatSTRK(fundTarget?.toString())} {tokenSymbol ? tokenSymbol.toString().toUpperCase() : "STRK"}</span>
                        </div>
                        <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-3">
                          <div 
                            className="bg-indigo-600 dark:bg-indigo-500 h-3 rounded-full transition-all duration-500 ease-in-out"
                            style={{ width: `${Math.min(fundBalance && fundTarget ? (Number(fundBalance.toString()) / Number(fundTarget.toString())) * 100 : 0, 100)}%` }}
                          ></div>
                        </div>
                      </div>

                      {/* Stats Grid */}
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
                          <div className="text-sm font-medium text-gray-500 dark:text-gray-400">Current Balance</div>
                          <div className="mt-1 flex items-baseline">
                            <span className="text-2xl font-semibold text-gray-900 dark:text-white">
                              {formatSTRK(fundBalance?.toString())}
                            </span>
                            <span className="ml-2 text-sm text-gray-500 dark:text-gray-400">{tokenSymbol ? tokenSymbol.toString().toUpperCase() : "STRK"}</span>
                          </div>
                        </div>
                        <div className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
                          <div className="text-sm font-medium text-gray-500 dark:text-gray-400">Time Remaining</div>
                          <div className="mt-1">
                            <div className="text-2xl font-bold tracking-tight">
                              <span className={`inline-flex items-center ${
                                remainingTime > 24 * 60 * 60 
                                  ? 'text-green-600 dark:text-green-400'
                                  : remainingTime > 0
                                    ? 'text-yellow-600 dark:text-yellow-400'
                                    : 'text-red-600 dark:text-red-400'
                              }`}>
                                {remainingTime > 0 ? '⏱ ' : '🔚 '}
                                {formatCountdown(remainingTime)}
                              </span>
                            </div>
                            <div className="mt-1">
                              <span className="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-blue-50/50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-200 border border-blue-100 dark:border-blue-800/30">
                                Deadline: {formatDeadline(deadline?.toString() || "")}
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* Donation Form */}
                      <div className="mt-auto">
                        <div className="flex flex-col space-y-4">
                          <InputBase
                            value={sendValue}
                            onChange={setSendValue}
                            placeholder={`Amount to donate (${tokenSymbol ? tokenSymbol.toString().toUpperCase() : "STRK"})`}
                            disabled={isLoading || isWriteLoading || isApproving}
                          />
                          <button
                            className={`w-full px-4 py-3 rounded-md text-white font-medium ${
                              isLoading || isWriteLoading || isApproving || !sendValue
                                ? 'bg-gray-400 cursor-not-allowed'
                                : 'bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500'
                            } transition-all duration-200`}
                            onClick={handleDonate}
                            disabled={isLoading || isWriteLoading || isApproving || !sendValue}
                          >
                            {isLoading || isWriteLoading || isApproving ? (
                              <span className="flex items-center justify-center">
                                <svg className="animate-spin -ml-1 mr-2 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                </svg>
                                Processing...
                              </span>
                            ) : (
                              `Donate ${tokenSymbol ? tokenSymbol.toString().toUpperCase() : "STRK"}`
                            )}
                          </button>
                          {error && (
                            <div className="text-red-500 text-sm bg-red-50 dark:bg-red-900/20 p-2 rounded-md">
                              {error}
                            </div>
                          )}
                        </div>

                        {/* Admin Controls */}
                        {isOwner && (
                          <div className="mt-4 flex justify-end gap-4">
                            <button
                              className={`inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm ${
                                isActive 
                                  ? 'text-white bg-red-600 hover:bg-red-700 focus:ring-red-500'
                                  : 'text-white bg-green-600 hover:bg-green-700 focus:ring-green-500'
                              } focus:outline-none focus:ring-2 focus:ring-offset-2 transition-all duration-200`}
                              onClick={handleToggleActive}
                              disabled={isLoading || isSettingActive}
                            >
                              {isLoading || isSettingActive ? (
                                <span className="flex items-center">
                                  <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                  </svg>
                                  Processing...
                                </span>
                              ) : (
                                isActive ? "Deactivate Funding" : "Activate Funding"
                              )}
                            </button>
                            <button
                              className={`inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm ${
                                isLoading || isWithdrawing || !fundBalance || 
                                BigInt(fundBalance.toString()) <= 0n ||
                                (fundTarget && deadline && BigInt(fundBalance.toString()) < BigInt(fundTarget.toString()) && 
                                 Date.now() / 1000 <= BigInt(deadline.toString()))
                                  ? 'bg-gray-400 cursor-not-allowed'
                                  : 'text-white bg-blue-600 hover:bg-blue-700 focus:ring-blue-500 focus:outline-none focus:ring-2 focus:ring-offset-2'
                              } transition-all duration-200`}
                              onClick={handleWithdraw}
                              disabled={isLoading || isWithdrawing || !fundBalance || 
                                      BigInt(fundBalance.toString()) <= 0n ||
                                      (fundTarget && deadline && BigInt(fundBalance.toString()) < BigInt(fundTarget.toString()) && 
                                       Date.now() / 1000 <= BigInt(deadline.toString()))}
                            >
                              {isLoading || isWithdrawing ? (
                                <span className="flex items-center">
                                  <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                  </svg>
                                  Processing...
                                </span>
                              ) : (
                                "Withdraw Funds"
                              )}
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="h-full max-w-4xl mx-auto flex items-center justify-center">
              <div className="bg-red-50 dark:bg-red-900/20 border-l-4 border-red-400 p-4 rounded-md">
                <div className="flex">
                  <div className="flex-shrink-0">
                    <svg className="h-5 w-5 text-red-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
                    </svg>
                  </div>
                  <div className="ml-3">
                    <h3 className="text-sm font-medium text-red-800 dark:text-red-200">
                      Funding Closed
                    </h3>
                    <div className="mt-2 text-sm text-red-700 dark:text-red-300">
                      This crowdfunding campaign is currently not active. Please check back later.
                    </div>
                  </div>
                </div>
                {/* Admin Controls */}
                {isOwner && (
                    <div className="mt-4 flex justify-end gap-4">
                      <button
                          className={`inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm ${
                              isActive
                                  ? 'text-white bg-red-600 hover:bg-red-700 focus:ring-red-500'
                                  : 'text-white bg-green-600 hover:bg-green-700 focus:ring-green-500'
                          } focus:outline-none focus:ring-2 focus:ring-offset-2 transition-all duration-200`}
                          onClick={handleToggleActive}
                          disabled={isLoading || isSettingActive}
                      >
                        {isLoading || isSettingActive ? (
                            <span className="flex items-center">
                                  <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                  </svg>
                                  Processing...
                                </span>
                        ) : (
                            isActive ? "Deactivate Funding" : "Activate Funding"
                        )}
                      </button>
                    </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Confirmation Modal */}
      {showConfirmDialog && pendingAmount && (
        <div className="fixed inset-0 overflow-y-auto z-50">
          <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            <div className="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"></div>
            <span className="hidden sm:inline-block sm:align-middle sm:h-screen">&#8203;</span>
            <div className="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full sm:p-6">
              <div>
                <div className="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-indigo-100 dark:bg-indigo-900">
                  <svg className="h-6 w-6 text-indigo-600 dark:text-indigo-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </div>
                <div className="mt-3 text-center sm:mt-5">
                  <h3 className="text-lg leading-6 font-medium text-gray-900 dark:text-white">
                    Confirm Donation
                  </h3>
                  <div className="mt-2">
                    <p className="text-sm text-gray-500 dark:text-gray-400">
                      Are you sure you want to donate {formatSTRK(pendingAmount.toString())} {tokenSymbol ? tokenSymbol.toString().toUpperCase() : "STRK"}?
                    </p>
                  </div>
                </div>
              </div>
              <div className="mt-5 sm:mt-6 sm:grid sm:grid-cols-2 sm:gap-3 sm:grid-flow-row-dense">
                <button
                  type="button"
                  className="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:col-start-2 sm:text-sm"
                  onClick={handleConfirmDonate}
                  disabled={isLoading}
                >
                  {isLoading ? "Processing..." : "Confirm"}
                </button>
                <button
                  type="button"
                  className="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:mt-0 sm:col-start-1 sm:text-sm"
                  onClick={handleCancel}
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Home;