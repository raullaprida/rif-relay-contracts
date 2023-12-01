import { HardhatEthersHelpers, HardhatRuntimeEnvironment } from 'hardhat/types';
import fs from 'node:fs';
import { ContractAddresses, NetworkConfig } from '../utils/scripts/types';
import { parseJsonFile } from './utils';
import { Overrides } from 'ethers';

const ADDRESS_FILE = process.env['ADDRESS_FILE'] || 'contract-addresses.json';

export type AddressesConfig = { [key: string]: ContractAddresses };

// TODO: Use the async version of fs.writeFile
export const writeConfigToDisk = (config: NetworkConfig) => {
  fs.writeFileSync(ADDRESS_FILE, JSON.stringify(config));
  console.log(`Address file available at: "${ADDRESS_FILE}"`);
};

export const updateConfig = async (
  contractAddresses: ContractAddresses,
  { hardhatArguments, config: { networks } }: HardhatRuntimeEnvironment
): Promise<NetworkConfig> => {
  console.log('Generating network config...');

  const { network } = hardhatArguments;
  if (!network) {
    throw new Error('Unknown Network');
  }
  const networkConfig = networks[network];
  if (!networkConfig) {
    throw new Error(`No network configuration found for ${network}`);
  }
  const { chainId } = networkConfig;

  if (!chainId) {
    throw new Error('Unknown Chain Id');
  }

  const existingConfig = (await new Promise<AddressesConfig>((resolve) => {
    resolve(parseJsonFile<AddressesConfig>(ADDRESS_FILE));
  }).catch(() =>
    console.log(`Previous configuration not found at: "${ADDRESS_FILE}"`)
  )) as AddressesConfig;

  return {
    ...existingConfig,
    [`${network}.${chainId}`]: contractAddresses,
  };
};

export const deployContracts = async (
  ethers: HardhatEthersHelpers,
  networkName?: string
): Promise<ContractAddresses> => {
  console.log('DEPLOYINg');
  const relayHubF = await ethers.getContractFactory('RelayHub');
  const penalizerF = await ethers.getContractFactory('Penalizer');
  const smartWalletF = await ethers.getContractFactory('SmartWallet');
  const smartWalletFactoryF = await ethers.getContractFactory(
    'SmartWalletFactory'
  );
  const deployVerifierF = await ethers.getContractFactory('DeployVerifier');
  const relayVerifierF = await ethers.getContractFactory('RelayVerifier');
  const utilTokenF = await ethers.getContractFactory('UtilToken');

  const overrides: Overrides = {
    gasPrice: '60000000',
    gasLimit: '6800000',
  };

  const customSmartWalletF = await ethers.getContractFactory(
    'CustomSmartWallet'
  );
  const customSmartWalletFactoryF = await ethers.getContractFactory(
    'CustomSmartWalletFactory'
  );
  const customSmartWalletDeployVerifierF = await ethers.getContractFactory(
    'CustomSmartWalletDeployVerifier'
  );
  const nativeHolderSmartWalletF = await ethers.getContractFactory(
    'NativeHolderSmartWallet'
  );

  const versionRegistryFactory = await ethers.getContractFactory(
    'VersionRegistry'
  );

  const { address: penalizerAddress } = await penalizerF.deploy(overrides);
  const { address: relayHubAddress } = await relayHubF.deploy(
    penalizerAddress,
    1,
    1,
    1,
    1,
    overrides
  );
  const { address: smartWalletAddress } = await smartWalletF.deploy(overrides);
  const { address: smartWalletFactoryAddress } =
    await smartWalletFactoryF.deploy(smartWalletAddress, overrides);
  const { address: deployVerifierAddress } = await deployVerifierF.deploy(
    smartWalletFactoryAddress,
    overrides
  );
  const { address: relayVerifierAddress } = await relayVerifierF.deploy(
    smartWalletFactoryAddress,
    overrides
  );

  const { address: customSmartWalletAddress } = await customSmartWalletF.deploy(
    overrides
  );
  const { address: customSmartWalletFactoryAddress } =
    await customSmartWalletFactoryF.deploy(customSmartWalletAddress, overrides);
  const { address: customDeployVerifierAddress } =
    await customSmartWalletDeployVerifierF.deploy(
      customSmartWalletFactoryAddress,
      overrides
    );
  const { address: customRelayVerifierAddress } = await relayVerifierF.deploy(
    customSmartWalletFactoryAddress,
    overrides
  );

  const { address: nativeHolderSmartWalletAddress } =
    await nativeHolderSmartWalletF.deploy(overrides);
  const { address: nativeHolderSmartWalletFactoryAddress } =
    await smartWalletFactoryF.deploy(nativeHolderSmartWalletAddress, overrides);
  const { address: nativeDeployVerifierAddress } = await deployVerifierF.deploy(
    nativeHolderSmartWalletFactoryAddress,
    overrides
  );
  const { address: nativeRelayVerifierAddress } = await relayVerifierF.deploy(
    nativeHolderSmartWalletFactoryAddress,
    overrides
  );

  const { address: versionRegistryAddress } =
    await versionRegistryFactory.deploy(overrides);

  let utilTokenAddress;
  if (networkName != 'mainnet') {
    const { address } = await utilTokenF.deploy(overrides);
    utilTokenAddress = address;
  }

  return {
    Penalizer: penalizerAddress,
    RelayHub: relayHubAddress,
    SmartWallet: smartWalletAddress,
    SmartWalletFactory: smartWalletFactoryAddress,
    DeployVerifier: deployVerifierAddress,
    RelayVerifier: relayVerifierAddress,
    CustomSmartWallet: customSmartWalletAddress,
    CustomSmartWalletFactory: customSmartWalletFactoryAddress,
    CustomSmartWalletDeployVerifier: customDeployVerifierAddress,
    CustomSmartWalletRelayVerifier: customRelayVerifierAddress,
    NativeHolderSmartWallet: nativeHolderSmartWalletAddress,
    NativeHolderSmartWalletFactory: nativeHolderSmartWalletFactoryAddress,
    NativeHolderSmartWalletDeployVerifier: nativeDeployVerifierAddress,
    NativeHolderSmartWalletRelayVerifier: nativeRelayVerifierAddress,
    UtilToken: utilTokenAddress,
    VersionRegistry: versionRegistryAddress,
  };
};

export const deploy = async (hre: HardhatRuntimeEnvironment) => {
  const {
    ethers,
    hardhatArguments: { network },
  } = hre;
  const contractAddresses = await deployContracts(ethers, network);
  console.table(contractAddresses);
  const newConfig = await updateConfig(contractAddresses, hre);
  writeConfigToDisk(newConfig);
};
