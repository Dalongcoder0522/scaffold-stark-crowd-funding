import {
  deployContract,
  executeDeployCalls,
  exportDeployments,
  deployer,
} from "./deploy-contract";
import { green } from "./helpers/colorize-log";
/**
 * Deploy a contract using the specified parameters.
 *
 * @example (deploy contract with contructorArgs)
 * const deployScript = async (): Promise<void> => {
 *   await deployContract(
 *     {
 *       contract: "YourContract",
 *       contractName: "YourContractExportName",
 *       constructorArgs: {
 *         owner: deployer.address,
 *       },
 *       options: {
 *         maxFee: BigInt(1000000000000)
 *       }
 *     }
 *   );
 * };
 *
 * @example (deploy contract without contructorArgs)
 * const deployScript = async (): Promise<void> => {
 *   await deployContract(
 *     {
 *       contract: "YourContract",
 *       contractName: "YourContractExportName",
 *       options: {
 *         maxFee: BigInt(1000000000000)
 *       }
 *     }
 *   );
 * };
 *
 *
 * @returns {Promise<void>}
 */
const deployScript = async (): Promise<void> => {
  await deployContract({
    contract: "crowdfunding",
    contractName: "crowdfunding",
    constructorArgs: {
      token: process.env.STRK_SEPOLIA_ADDRESS,
      grantee_address: process.env.GRANTEE_ADDRESS,
      fund_target: BigInt(process.env.FUND_TARGET ?? "100000000000000000000"),
      fund_description: process.env.FUND_DESCRIPTION,
      deadline: process.env.DEADLINE ?? "1767151217",
      initial_owner: deployer.address,
    },
/*    options: {
      maxFee: BigInt("1000000000000000000000000000000")
    }*/
  });
};

deployScript()
  .then(async () => {
    executeDeployCalls()
      .then(() => {
        exportDeployments();
        console.log(green("All Setup Done"));
      })
      .catch((e) => {
        console.error(e);
        process.exit(1); // exit with error so that non subsequent scripts are run
      });
  })
  .catch(console.error);
