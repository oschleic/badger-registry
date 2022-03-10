// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";


contract BadgerRegistry {
  using EnumerableSet for EnumerableSet.AddressSet;

  //@dev is the vault at the experimental, guarded or open stage? Only for Prod Vaults
  enum VaultStatus { experimental, guarded, open, deprecated }

  struct VaultData {
    string version;
    VaultStatus status;
    address[] list;
  }

  //@dev Multisig. Vaults from here are considered Production ready
  address public governance;
  address public devGovernance; //@notice an address with some powers to make things easier in development
  address public strategistGuild;

  //@dev Given an Author Address, and Token, Return the Vault
  mapping(address => mapping(string => EnumerableSet.AddressSet)) private vaults;
  mapping(address => string) private metadata;
  mapping(string => address) public addresses;
  mapping(address => string) public keys;

  //@dev Given Version and VaultStatus, returns the list of Vaults in production
  mapping(string => mapping(VaultStatus => EnumerableSet.AddressSet)) private productionVaults;

  // Known constants you can use
  string[] public versions; //@notice, you don't have a guarantee of the key being there, it's just a utility

  event NewVault(address author, string version, address vault);
  event RemoveVault(address author, string version, address vault);
  event PromoteVault(address author, string version, address vault, VaultStatus status);
  event DemoteVault(address author, string version, address vault, VaultStatus status);

  event Set(string key, address at);
  event AddKey(string key);
  event DeleteKey(string key);
  event AddVersion(string version);


  function setStrategeistGuild(address newStrategistGuild) public {
    require(msg.sender == governance, "!gov");
    strategistGuild = newStrategistGuild;
  }

  function initialize(address newGovernance) public {
    require(governance == address(0));
    governance = newGovernance;
    devGovernance = address(0);

    versions.push("v1"); //For v1
    versions.push("v2"); //For v2
  }

  function setGovernance(address _newGov) public {
    require(msg.sender == governance, "!gov");
    governance = _newGov;
  }

  function setDev(address newDev) public {
    require(msg.sender == governance || msg.sender == devGovernance, "!gov");
    devGovernance = newDev;
  }

  //@dev Utility function to add Versions for Vaults,
  //@notice No guarantee that it will be properly used
  function addVersions(string memory version) public {
    require(msg.sender == governance, "!gov");
    versions.push(version);

    emit AddVersion(version);
  }


  //@dev Anyone can add a vault to here, it will be indexed by their address
  function add(string memory version, address vault, string memory data) public {
    bool added = vaults[msg.sender][version].add(vault);
    if (added) {
      metadata[vault] = data;
      emit NewVault(msg.sender, version, vault);
    }
  }

  //@dev Remove the vault from your index
  function remove(string memory version, address vault) public {
    bool removed = vaults[msg.sender][version].remove(vault);
    if (removed) {
      delete metadata[vault]; //Does this need to be removed?
      emit RemoveVault(msg.sender, version, vault);
     }
  }

  //@dev Promote a vault to Production
  //@dev Promote just means indexed by the Governance Address
  function promote(string memory version, address vault, VaultStatus status, string memory data) public {
    require(msg.sender == governance || msg.sender == devGovernance || msg.sender == strategistGuild, "!gov");

    VaultStatus actualStatus = status;
    if(msg.sender == devGovernance) {
      actualStatus = VaultStatus.experimental;
    }

    bool added = productionVaults[version][actualStatus].add(vault);

    // If added remove from old and emit event
    if (added) {
      metadata[vault] = data;
      // also remove from old prod
      if(uint256(actualStatus) == 3){
        // Remove from prev3
        productionVaults[version][VaultStatus(0)].remove(vault);
        productionVaults[version][VaultStatus(1)].remove(vault);
        productionVaults[version][VaultStatus(2)].remove(vault);
      }
      if(uint256(actualStatus) == 2){
        // Remove from prev2
        productionVaults[version][VaultStatus(0)].remove(vault);
        productionVaults[version][VaultStatus(1)].remove(vault);
      }
      if(uint256(actualStatus) == 1){
        // Remove from prev1
        productionVaults[version][VaultStatus(0)].remove(vault);
      }

      emit PromoteVault(msg.sender, version, vault, actualStatus);
    }
  }

  function demote(string memory version, address vault, VaultStatus status) public {
    require(msg.sender == governance || msg.sender == devGovernance, "!gov");

    VaultStatus actualStatus = status;
    if(msg.sender == devGovernance) {
      actualStatus = VaultStatus.experimental;
    }

    bool removed = productionVaults[version][actualStatus].remove(vault);

    if (removed) {
      emit DemoteVault(msg.sender, version, vault, status);
    }
  }

  /** KEY Management */

  //@dev Set the value of a key to a specific address
  //@notice e.g. controller = 0x123123
  function set(string memory key, address at) public {
    require(msg.sender == governance, "!gov");
    addresses[key] = at;
    keys[at] = key;
    emit Set(key, at);
  }

  //@dev Delete a key
  function deleteKey(string memory key) public {
    require(msg.sender == governance, "!gov");
    address keyAddress = addresses[key];
    delete addresses[key];
    delete keys[keyAddress];
    emit DeleteKey(key);
  }


  //@dev Retrieve the value of a key
  function getAddress(string memory key) public view returns (address){
    return addresses[key];
  }

  //@dev Retrieve the key from the address
  function getKey(address keyAddress) public view returns (string memory){
    return keys[keyAddress];
  }

  //@dev Retrieve a list of all Vault Addresses from the given author along with metadata
  function getVaults(string memory version, address author) public view returns (address[] memory, string[] memory) {
    uint256 length = vaults[author][version].length();

    address[] memory list = new address[](length);
    string[] memory metadataList = new string[](length);
    for (uint256 i = 0; i < length; i++) {
      list[i] = vaults[author][version].at(i);
      metadataList[i] = metadata[list[i]];
    }
    return (list, metadataList);
  }

  //@dev Retrieve a list of all Vaults that are in production along with their metadata, based on Version and Status
  function getFilteredProductionVaults(string memory version, VaultStatus status) public view returns (address[] memory, string[] memory) {
    uint256 length = productionVaults[version][status].length();

    address[] memory list = new address[](length);
    string[] memory metadataList = new string[](length);
    for (uint256 i = 0; i < length; i++) {
      list[i] = productionVaults[version][status].at(i);
      metadataList[i] = metadata[list[i]];
    }
    return (list, metadataList);
  }

  function getProductionVaults() public view returns (VaultData[] memory, string[] memory) {
    uint256 versionsCount = versions.length;

    VaultData[] memory data = new VaultData[](versionsCount * 3);
    string[] memory metadataList;

    for(uint256 x = 0; x < versionsCount; x++) {
      for(uint256 y = 0; y < 3; y++) {
        uint256 length = productionVaults[versions[x]][VaultStatus(y)].length();
        address[] memory list = new address[](length);
        metadataList = new string[](length);
        for(uint256 z = 0; z < length; z++){
          list[z] = productionVaults[versions[x]][VaultStatus(y)].at(z);
          metadataList[z] = metadata[list[z]];
        }
        data[x * (versionsCount - 1) + y * 2] = VaultData({
          version: versions[x],
          status: VaultStatus(y),
          list: list
        });
      }
    }

    return (data, metadataList);
  }
}