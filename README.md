## Invnex

**The Invnex TokenFactory contract is designed to facilitate the creation, listing, and management of ERC20 tokens. It allows for deploying new tokens, managing Initial Coin Offerings (ICOs), buying tokens, and claiming purchased tokens.**

## 🛠️ Getting Started

**To interact with the Invnex TokenFactory, ensure you have the following:**

-  A Solidity development environment like Remix or vscode.
-  A wallet (e.g., MetaMask) connected to a blockchain network.

-   **Installation**: 

    **Install Foundry by running the command:**
    ```shell
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
    ```

    ```shell
    $ git clone https://github.com/Carbon-Sarhat/Invnex_Contracts.git
    ```

    ```shell
    $ cd Invnex_Contracts
    ```

## Documentation

Detailed documentation for the Invnex TokenFactory contract, including all functions and parameters, can be found [here](https://github.com/Carbon-Sarhat/Invnex_Contracts/blob/main/Invnex_Docs.pdf)

## 💻 Usage

**Deploying the Contract**
- Compile the contract using your preferred Solidity environment.
- Deploy the TokenFactory contract to your desired blockchain network.

**Creating a New Token**
- Call the deployToken function with:
    - name: The name of the token.
    - symbol: The token's symbol.
    - address: owner of the token(could be individual/institution)
    - initialSupply: The initial supply of the token.

**Managing ICOs**
- Use the startICO function to set up and launch an ICO:
    - Specify the token price, duration, and fundraising goal.
- Monitor the status of the ICO through getICOStatus.

**Buying Tokens**
- Users can purchase tokens during an active ICO by sending funds to the buyTokens function.

**Claiming Tokens**
- After the ICO ends, users can claim their purchased tokens via the claimTokens function.

### Generating the ABI of Smart Contracts Using Foundry in VS Code

**Compile the Contract**

```shell
$ forge build
```
- This command:

    - Compiles the contracts in the src directory.
    - Outputs the build artifacts (including the ABI) to the out directory.

**Locate the ABI**
- Once the build is complete, the ABI is generated in the out directory.

    - Open the out directory in your Foundry project.
    - Locate the JSON file corresponding to "Invnex.sol" contract.
    - Open the JSON file. The ABI is located in the "abi" field.

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/fileName:contractName --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
