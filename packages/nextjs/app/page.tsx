'use client';

import { ConnectedAddress } from "~~/components/ConnectedAddress";
import { InputBase } from "~~/components/scaffold-stark";
import { useState, useMemo } from "react";
import { useScaffoldReadContract, useScaffoldWriteContract, useDeployedContractInfo } from "~~/hooks/scaffold-stark";
import { useAccount } from "~~/hooks/useAccount";
import GenericModal from "~~/components/scaffold-stark/CustomConnectButton/GenericModal";

// 将 felt252 转换为字符串
const feltToString = (felt: string) => {
  const hex = BigInt(felt).toString(16);
  const paddedHex = hex.length % 2 ? '0' + hex : hex;
  const bytes = [];
  for (let i = 0; i < paddedHex.length; i += 2) {
    bytes.push(parseInt(paddedHex.slice(i, i + 2), 16));
  }
  return new TextDecoder().decode(new Uint8Array(bytes));
};

// 格式化 STRK 金额
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

const Home = () => {
  const [sendValue, setSendValue] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pendingAmount, setPendingAmount] = useState<bigint | null>(null);
  const [showConfirmDialog, setShowConfirmDialog] = useState(false);
  const { address } = useAccount();
  
  // 获取 crowdfunding 合约地址
  const { data: crowdfundingContract } = useDeployedContractInfo("crowdfunding");

  // 读取众筹描述
  const { data: fundDescription, isLoading: isLoadingDescription } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_fund_description",
  });

  // 获取合约余额
  const { data: fundBalance, isLoading: isLoadingBalance } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_fund_balance",
  });

  // 获取代币符号
  const { data: tokenSymbol, isLoading: isLoadingSymbol } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_token_symbol",
  });

  // 获取活动状态
  const { data: isActive } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_active",
  });

  // 动态确定代币合约名称
  const tokenContractName = useMemo(() => {
    debugger;
    if (!tokenSymbol) return "Strk"; // 默认使用 STRK
    const symbol = tokenSymbol.toString().toUpperCase();
    if (symbol === "ETH") return "Eth";
    if (symbol === "STRK") return "Strk";
    return "Strk";
  }, [tokenSymbol]) as "Eth" | "Strk";

  // 获取目标金额
  const { data: fundTarget, isLoading: isLoadingTarget } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_fund_target",
  });

  // 获取截止时间
  const { data: deadline } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_deadline",
  });

  // ERC20 approve
  const { sendAsync: approveToken, isPending: isApproving } = useScaffoldWriteContract({
    contractName: tokenContractName,
    functionName: "approve",
    args:  [crowdfundingContract?.address, 0n] as const
  });

  // 捐赠功能
  const { sendAsync: fundToContract, isPending: isWriteLoading } = useScaffoldWriteContract({
    contractName: "crowdfunding",
    functionName: "fund_to_contract",
    args: [0n] as const
  });

  // 获取合约拥有者
  const { data: initialOwner } = useScaffoldReadContract({
    contractName: "crowdfunding",
    functionName: "get_owner",
  });

  // 提现功能
  const { sendAsync: withdrawFunds, isPending: isWithdrawing } = useScaffoldWriteContract({
    contractName: "crowdfunding",
    functionName: "withdraw_funds",
  });

  // 激活/停用功能
  const { sendAsync: setActive, isPending: isSettingActive } = useScaffoldWriteContract({
    contractName: "crowdfunding",
    functionName: "set_active",
    args: [true] as const
  });

  // 处理激活状态切换
  const handleToggleActive = async () => {
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

  // 转换描述为可读字符串
  const description = fundDescription ? feltToString(fundDescription.toString()) : "Loading...";
  
  // 处理代币符号
  const symbol = useMemo(() => {
    if (!tokenSymbol) return "STRK";
    try {
      return tokenSymbol.toString().toUpperCase();
    } catch (error) {
      console.error("Error parsing token symbol:", error);
      return "STRK";
    }
  }, [tokenSymbol]);

  // 计算进度
  const progress = fundBalance && fundTarget ?
    (Number(fundBalance.toString()) / Number(fundTarget.toString())) * 100 : 0;

  // 格式化截止时间
  const formatDeadline = (timestamp: string) => {
    if (!timestamp) return "Loading...";
    const date = new Date(Number(timestamp) * 1000);
    return date.toLocaleDateString() + " " + date.toLocaleTimeString();
  };

  // 使用 useMemo 缓存加载状态
  const isPageLoading = useMemo(() => {
    // 只在初始加载时显示加载状态
    if (!crowdfundingContract) return true;
    
    // 如果已经有数据，即使在加载中也不显示加载状态
    if (fundDescription || fundBalance || tokenSymbol || fundTarget) return false;
    
    // 否则根据加载状态判断
    return isLoadingDescription || isLoadingBalance || isLoadingTarget || isLoadingSymbol;
  }, [
    crowdfundingContract,
    fundDescription,
    fundBalance,
    tokenSymbol,
    fundTarget,
    isLoadingDescription,
    isLoadingBalance,
    isLoadingTarget,
    isLoadingSymbol
  ]);

  // 检查是否是合约拥有者
  const isOwner = useMemo(() => {
    if (!initialOwner || !address) return false;
    // 将 initialOwner（十进制）转换为 16 进制
    const ownerHex = "0x" + BigInt(initialOwner.toString()).toString(16).padStart(64, '0');
    // address 已经是 16 进制，但确保格式统一
    const addressHex = address.toLowerCase();
    return ownerHex.toLowerCase() === addressHex;
  }, [initialOwner, address]);

  // 处理捐赠
  const handleDonate = async () => {
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

  // 处理取消
  const handleCancel = () => {
    setShowConfirmDialog(false);
    setPendingAmount(null);
    setIsLoading(false);
  };

  // 处理确认捐赠
  const handleConfirmDonate = async () => {
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

  // 处理提现
  const handleWithdraw = async () => {
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

  return (
    <div className="flex items-center flex-col flex-grow pt-10">
      <div className="px-5">
        <h1 className="text-center">
          <span className="text-2xl mb-2">Welcome to </span>
          <span className="text-4xl font-bold">
            {description}
          </span>
          <span className="text-2xl mb-2"> Starknet CrowdFunding</span>
        </h1>
        <ConnectedAddress />
        
        {/* Toggle Active Button - 只对合约拥有者显示 */}
        {isOwner && (
          <div className="mt-4">
            <button
              className={`btn ${isActive ? 'btn-warning' : 'btn-success'} mt-4`}
              onClick={handleToggleActive}
              disabled={isLoading || isSettingActive}
            >
              {isLoading || isSettingActive ? "Processing..." : (isActive ? "Deactivate Funding" : "Activate Funding")}
            </button>
          </div>
        )}
        
        {isActive ? (
          // 当 active 为 true 时显示原有内容
          <>
            {isPageLoading ? (
              <div className="text-center mt-8">Loading campaign details...</div>
            ) : (
              <>
                {/* 显示进度和目标 */}
                <div className="mt-8 w-full max-w-lg mx-auto">
                  <div className="flex justify-between mb-2">
                    <span>Progress: {progress.toFixed(2)}%</span>
                    <span>Target: {formatSTRK(fundTarget?.toString())} {symbol}</span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2.5 dark:bg-gray-700">
                    <div 
                      className="bg-blue-600 h-2.5 rounded-full transition-all duration-500" 
                      style={{ width: `${Math.min(progress, 100)}%` }}
                    ></div>
                  </div>
                </div>

                {/* 显示余额和截止时间 */}
                <div className="mt-4 flex flex-col items-center gap-2">
                  <div className="font-bold mt-4">Funding Balance: {formatSTRK(fundBalance?.toString())} {symbol}</div>
                  <div className="text-sm">Deadline: {formatDeadline(deadline?.toString() || "")}</div>
                  
                  {/* 提现按钮 - 只对合约拥有者显示 */}
                  {isOwner && (
                    <button
                      className="btn btn-secondary mt-4"
                      onClick={handleWithdraw}
                      disabled={isLoading || isWithdrawing || !fundBalance || BigInt(fundBalance.toString()) <= 0n}
                    >
                      {isLoading || isWithdrawing ? "Processing..." : "Withdraw Funds"}
                    </button>
                  )}
                </div>

                {/* 捐赠输入和按钮 */}
                <div className="mt-4 flex flex-col items-center gap-4">
                  <InputBase
                    value={sendValue}
                    onChange={setSendValue}
                    placeholder={`Amount to donate (${symbol})`}
                    disabled={isLoading || isWriteLoading || isApproving}
                    suffix={
                      <button
                        className="btn btn-primary h-[2.2rem] min-h-[2.2rem]"
                        onClick={handleDonate}
                        disabled={isLoading || isWriteLoading || isApproving || !sendValue}
                      >
                        {isLoading || isWriteLoading || isApproving ? "Processing..." : `Donate ${symbol}`}
                      </button>
                    }
                  />
                  {error && <div className="text-red-500 text-sm">{error}</div>}
                </div>
              </>
            )}
          </>
        ) : (
          // 当 active 为 false 时只显示关闭信息
          <div className="text-center text-red-500 font-bold mt-8">
            Current funding is closed
          </div>
        )}
      </div>

      {/* 确认对话框 */}
      <input 
        type="checkbox" 
        id="confirm-modal" 
        className="modal-toggle" 
        checked={showConfirmDialog} 
        onChange={handleCancel}
      />
      {showConfirmDialog && pendingAmount && (
        <GenericModal 
          modalId="confirm-modal" 
          className="modal-box bg-base-100 p-6 rounded-lg shadow-xl max-w-sm w-full"
        >
          <h3 className="text-lg font-bold mb-4">Confirm Donation</h3>
          <p className="mb-4">
            Are you sure you want to donate {formatSTRK(pendingAmount.toString())} {symbol}?
          </p>
          <div className="flex justify-end gap-4">
            <button
              className="btn btn-ghost"
              onClick={handleCancel}
            >
              Cancel
            </button>
            <button
              className="btn btn-primary"
              onClick={handleConfirmDonate}
              disabled={isLoading}
            >
              {isLoading ? "Processing..." : "Confirm"}
            </button>
          </div>
        </GenericModal>
      )}
    </div>
  );
};

export default Home;