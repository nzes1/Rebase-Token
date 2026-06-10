# Cross-Chain Rebase Token Protocol

A sophisticated DeFi protocol that combines **dynamic token rebasing** with **cross-chain interoperability** using Chainlink CCIP (Cross-Chain Interoperability Protocol). Users deposit ETH into a vault to earn linearly accruing interest represented by Rebase Tokens (RBT), which can be seamlessly bridged across EVM chains while preserving individual reward rates.

## 🎯 Project Overview

### What Is This?

This is a production-ready exploration of advanced Solidity patterns learned from [Cyfrin Updraft's Advanced Foundry Course](https://updraft.cyfrin.io/courses/advanced-foundry) and extended with deep cross-chain functionality. The protocol demonstrates:

1. **Dynamic Rebasing Tokens** — balanceOf() returns real-time accrued interest
2. **Per-User Interest Rates** — each depositor gets a fixed rate at deposit time, incentivizing early adoption
3. **CCIP Burn-Mint Bridging** — seamlessly transfer RBTs across chains with interest rate preservation
4. **Solidity Best Practices** — role-based access control, precision fixed-point math, comprehensive testing

### Key Features

- 💰 **Vault System** — Deposit ETH, mint Rebase Tokens with linear interest accrual
- 🌍 **Cross-Chain Messaging** — Transfer tokens between Ethereum Sepolia and Arbitrum Sepolia
- 📈 **Linear Interest Model** — Simple interest accrues per second; interest is minted on-demand
- 🔗 **Interest Rate Preservation** — Interest rates follow tokens across chains, maintaining reward consistency
- 🛡️ **Role-Based Access Control** — Owner controls protocol params, separate roles for minting/burning
- 🧪 **Comprehensive Testing** — Both unit and integration tests with Chainlink's local fork simulator

---

## 🏗️ Architecture

### System Design

```
┌─────────────────┐
│    Vault        │  Accepts ETH deposits
└────────┬────────┘
         │ Mints RBT
         ↓
┌──────────────────────┐
│  RebaseToken (RBT)   │  ERC20 with dynamic balanceOf()
└────────┬─────────────┘
         │ Cross-chain transfer
         ↓
┌──────────────────────────────────────┐
│ BurnMintRebaseTokenPool              │  CCIP TokenPool override
│ (Burn on source, Mint on dest)       │
└──────────────────────────────────────┘
         │ CCIP Message
         ↓
┌──────────────────────┐
│   Remote Chain       │  Destination RBT minted
│ with Remote Pool     │
└──────────────────────┘
```

### Smart Contracts

#### **RebaseToken.sol** — The Core Rebase Mechanism
- **ERC20 Extension**: Standard token interface with dynamic balancing
- **Interest Accrual**: `balanceOf()` calculates real-time balance = principal × (1 + rate × time)
- **Per-User Tracking**:
  - `s_userInterestRates` — individual interest rate fixed at first deposit/transfer
  - `s_userLastUpdatedAt` — timestamp of last interest minting
  - Separation of principal (standard balance) from accrued interest
- **Interest Model** — Linear (simple) interest, **NOT compound**:
  - Formula: `balance = principal * (1e18 + rate * elapsedSeconds) / 1e18`
  - Interest only mints when user takes an action (deposit, transfer, burn, etc.)
  - This creates a "virtual" compound effect if users repeatedly trigger minting
- **Governance**: Owner can only *decrease* global interest rate (rewards early adopters)

**Key Functions**:
```solidity
balanceOf(address) → uint256              // Current balance with interest
setInterestRate(uint256) → void           // Owner-only, must decrease
mint(address, uint256, uint256) → void    // Requires MINT_AND_BURN_ROLE
burn(address, uint256) → void             // Requires MINT_AND_BURN_ROLE
```

#### **Vault.sol** — Entry/Exit Point
- Simple ETH ↔ RBT exchange at 1:1 ratio (before interest accrual)
- Mints RBTs with current global interest rate on deposit
- Burns RBTs and returns ETH on redemption
- Receives ETH deposits directly via `receive()` for reward accumulation

**Key Functions**:
```solidity
deposit() payable → void                  // Convert ETH → RBT
redeem(uint256) → void                    // Convert RBT → ETH (supports type(uint256).max)
```

#### **BurnMintRebaseTokenPool.sol** — CCIP Integration
Overrides Chainlink's TokenPool to handle rebasing logic:

- **lockOrBurn()**: On outbound transfers
  - Retrieves sender's interest rate
  - Burns RBTs from the pool
  - Encodes sender's rate in `destPoolData` for destination chain

- **releaseOrMint()**: On inbound transfers
  - Decodes recipient's interest rate from source chain
  - Mints RBTs with the sender's rate (recipient inherits sender's rate)
  - Validates amount without decimal conversion (interest rate is passed instead)

**Design Decision**: Interest rates are encoded in pool metadata, not stored on-chain per destination. This ensures recipients automatically inherit the sender's rate, maintaining reward consistency.

---

## 🚀 Getting Started

### Prerequisites

- **Foundry** (v0.2.0+) — Smart contract development framework
  - Install: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- **Node.js** (v18+) — Required by Chainlink Local Simulator

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd rebase-token

# Install dependencies (Foundry submodules)
git submodule update --init --recursive

# Verify installation
forge --version
```

### Dependencies

All dependencies are git submodules in `lib/`:
- `openzeppelin-contracts` — ERC20, AccessControl, Ownable
- `chainlink-ccip` — CCIP contracts and interfaces
- `chainlink-local` — Local fork simulator for testing
- `forge-std` — Foundry standard library

### Environment Setup

The project uses RPC endpoints from **Alchemy** (configured in `foundry.toml`):

```toml
[rpc_endpoints]
eth_sepolia_rpc = "https://eth-sepolia.g.alchemy.com/v2/..."
arbitrum_sepolia_rpc = "https://arb-sepolia.g.alchemy.com/v2/..."
```

**To use your own RPC endpoints**, update `foundry.toml` or set environment variables:
```bash
export ETH_SEPOLIA_RPC_URL="your-rpc-url"
export ARBITRUM_SEPOLIA_RPC_URL="your-rpc-url"
```

---

## 🧪 Testing

### Running Tests

```bash
# Run all tests (unit + integration)
forge test

# Run only unit tests
forge test --match-contract RebaseTokenUnitTest

# Run only cross-chain integration tests
forge test --match-contract CrossChainTest

# Run with verbose output
forge test -vv

# Run with more detailed logging
forge test -vvv
```

### Chainlink Local Simulator Setup

The integration tests use **CCIPLocalSimulatorFork** from Chainlink to simulate cross-chain messaging locally. This is crucial because:

1. **No testnet dependency** — Tests run in local forks of mainnet/testnet
2. **Full CCIP simulation** — Validates all Chainlink CCIP contracts and state changes
3. **Fork-to-fork routing** — Messages route between two separate fork instances

**Key test setup**:
```solidity
ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
vm.makePersistent(address(ccipLocalSimulatorFork));

ethSepoliaFork = vm.createSelectFork("eth_sepolia_rpc");
arbSepoliaFork = vm.createFork("arbitrum_sepolia_rpc");
```

The `CCIPLocalSimulatorFork` automatically:
- Deploys Chainlink contracts (Router, TokenAdminRegistry, etc.) on both forks
- Provides network details (chain selector, RMN proxy, etc.)
- Routes messages between fork chains via `switchChainAndRouteMessage()`

### Test Coverage

#### **Unit Tests** (`test/unit/RebaseTokenUnitTests.t.sol`)
- Linear interest accrual with fuzzing
- Deposit, transfer, and redemption flows
- Interest rate preservation and inheritance
- Access control for mint/burn operations
- Vault event emissions

#### **Integration Tests** (`test/integration/CrossChainTest.t.sol`)
- Vault deposit on source chain
- Cross-chain token bridging
- Interest rate preservation across chains
- Balance validation after bridging
- CCIP message routing and token minting

**Running with specific parameters**:
```bash
# Increase fuzz runs (default: 512)
forge test --fuzz-runs 10000

# Run single test
forge test --match-test testBridgeAllTokensFromSepoliaToArbitrumSepolia -vvv
```

---

## 🔧 Configuration

### Foundry Config (`foundry.toml`)

```toml
# Compiler and output
src = "src"
out = "out"
libs = ["lib"]

# Ignore low-level call return warnings
ignored_error_codes = [9302]

# Formatter settings
[fmt]
line_length = 120
wrap_comments = true
sort_imports = true

# Linter settings
[lint]
exclude_lints = ["screaming-snake-case-immutable"]

# Fuzz testing
[fuzz]
runs = 512  # Number of fuzz iterations per test

# RPC Endpoints (update with your own)
[rpc_endpoints]
eth_sepolia_rpc = "https://eth-sepolia.g.alchemy.com/v2/..."
arbitrum_sepolia_rpc = "https://arb-sepolia.g.alchemy.com/v2/..."
```

### Key Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `src` | `src/` | Solidity source directory |
| `out` | `out/` | Compiled artifacts output |
| `libs` | `["lib/"]` | Dependency directories |
| `line_length` | `120` | Maximum line length for formatting |
| `fuzz.runs` | `512` | Number of fuzzing iterations per test |

---

## 📊 Design Details & Trade-Offs

### Interest Rate Model

**Why Linear, Not Compound?**

Linear (simple) interest is chosen for clarity and predictability:
- **Simple**: interest = principal × rate × time
- **Predictable**: Easy for users to calculate expected rewards
- **Demo-friendly**: Suitable for portfolio projects

**However**, due to the design of interest minting:
- Interest is only minted when users trigger actions (transfer, redeem, etc.)
- Each action "compounds" — new interest is calculated on principal + previously accrued interest
- This creates an **apparent compound effect** while maintaining the linear calculation model

**Example**:
```
Day 1: Deposit 100 RBT at 5% per day
       After 1 day: 105 RBT (minted 5 interest)
       
Day 2: Transfer tokens (triggers minting)
       Updated balance: 110 RBT (5 interest minted on new 105 principal)
       
Day 3: After no actions, balance still shows 115 RBT
       But only 110 is "minted" — 5 is virtual
```

**Note**: For production, consider implementing true linear accrual with off-chain rewards distribution or a yield-bearing token wrapper.

### Known Issues & Design Decisions

#### 1. **Interest Rate Arbitrage** ⚠️
Users can exploit the transfer mechanism:

**Scenario**:
1. Deposit early with wallet A → rate = 5%
2. Use wallet B to deposit late → rate = 3%
3. Transfer all tokens from B to A → A's rate becomes 3%

**Why it happens**: When recipient has zero balance, they inherit sender's rate. This allows late depositors to "steal" early rates if they had previously deposited with another wallet.

**Why it's acceptable**: This is a known limitation in demo/educational projects. Full mitigation would require:
- Weighted average rates across multiple deposits
- Rate locking per deposit tranche
- Governance mechanisms for rate changes

**For production**: Implement rate batching or tiered vesting.

#### 2. **Principal Balance vs. Accrued Interest** ℹ️
The protocol separates:
- **Principal** — stored in standard ERC20 balance
- **Accrued interest** — calculated dynamically in `balanceOf()`

This means `totalSupply()` does NOT reflect true protocol wealth — only principal is counted. Interest is "virtual" until minted via user actions.

#### 3. **Centralization Risk** 🔒
- Owner controls global interest rate (mitigated: can only decrease)
- Admin controls minting/burning roles
- No circuit breakers or emergency mechanisms yet

**Recommendations**:
- Move to DAO governance for rate changes
- Implement timelock for admin actions
- Add pausing mechanisms for security

#### 4. **Decimal Handling in CCIP** 🔄
Standard Chainlink TokenPool converts amounts across different decimal chains. Our implementation:
- Assumes same decimals (18) on source and destination
- Passes interest rate in `sourcePoolData` instead of remote decimals
- Skips `_calculateLocalAmount()` to avoid decimal mismatch bugs

If bridging to chains with different decimals, you must implement proper decimal scaling.

---

## 🐛 Known Bugs & Quirks

### Address Encoding Bug in Token Pool Configuration
**Status**: ⚠️ **Unresolved**

When configuring remote token addresses in `TokenPool.applyChainUpdates()`, there's a subtle encoding issue:

```solidity
// Current (works, but inconsistent):
remoteTokenAddress: abi.encode(_remoteTokenAddress)

// Issue: abi.encode pads 20-byte address to 32 bytes
// 0x6E1734... → 0x0000...6E1734...
```

**Root cause**: The local simulator expects `abi.encodePacked` for pool validation but `abi.encode` for token addresses. This inconsistency can cause message encoding failures in certain scenarios.

**Workaround**: Use `abi.encode()` as currently implemented — it works with the local simulator despite the inconsistency.

**Future fix**: Await Chainlink's standardization of address encoding in TokenPool contracts.

---

## 📚 Learning Resources

This project heavily leverages learnings from:

### **Chainlink Documentation**
- [CCIP Overview](https://docs.chain.link/ccip) — Cross-chain fundamentals
- [TokenPool Architecture](https://docs.chain.link/ccip/concepts#token-pools) — Token bridging patterns
- [CCIP Local Simulator](https://docs.chain.link/ccip/test-locally) — Local testing setup
- [Burn-Mint Bridging](https://docs.chain.link/ccip/usdc-burn-mint) — Token pool patterns

### **Cyfrin Updraft Advanced Foundry**
- [Advanced Foundry Course](https://updraft.cyfrin.io/courses/advanced-foundry) — Foundation for contract patterns
- Rebase token mechanics inspired by staking rewards patterns
- CCIP integration demonstrates advanced inter-protocol communication

### **Solidity Best Practices**
- Role-based access control via OpenZeppelin's AccessControl
- Reentrancy guards and call safety patterns
- Fixed-point arithmetic for interest calculations
- ERC20 extension patterns

---

## 🔬 Interest Accrual Deep Dive

### How `balanceOf()` Works

```solidity
balance = principal × (1 + rate × time)
```

Where:
- `principal` = user's minted RBT balance (from ERC20.balanceOf())
- `rate` = user's interest rate (set at deposit/transfer, per-second)
- `time` = seconds since last interest minting

### Fixed-Point Implementation

To handle decimals in Solidity:

```solidity
interestFactor = 1e18 + (rate × elapsedSeconds)
balance = principal × interestFactor / 1e18
```

**Example**:
```
principal = 100 tokens (1e20 wei)
rate = 5e10 per second (0.00000005%)
elapsedSeconds = 86400 (1 day)

interestFactor = 1e18 + (5e10 × 86400)
               = 1e18 + 432e14
               = 1e18 + 4.32e15
               ≈ 1.00000432e18

balance = (1e20 × 1.00000432e18) / 1e18
        ≈ 1.00000432e20 wei
        ≈ 100.00432 tokens
```

### Interest Minting Mechanism

`_mintAccruedInterest()` is called before any balance-changing operation:

```solidity
previousBalance = super.balanceOf(user)      // Minted tokens only
currentBalance = balanceOf(user)             // Includes virtual interest
interestToMint = currentBalance - previousBalance
_mint(user, interestToMint)                  // Realize the virtual interest
```

This "compounding" effect comes from re-calculating interest on the newly minted amount.

---

## 🌐 Cross-Chain Flow

### Bridging Process

1. **User initiates transfer** (Ethereum Sepolia):
   - Approves Router to spend RBTs
   - Calls `router.ccipSend(destinationChainSelector, message)`

2. **Source chain processes**:
   - Router checks TokenPool for this token
   - Calls `BurnMintRebaseTokenPool.lockOrBurn()`
   - Tokens are burned, interest rate encoded in message

3. **CCIP messaging**:
   - Message routed through Chainlink network
   - Local simulator: `switchChainAndRouteMessage()` delivers to destination fork

4. **Destination chain processes**:
   - Router calls `BurnMintRebaseTokenPool.releaseOrMint()`
   - Tokens minted to recipient with sender's interest rate
   - Event emitted, balance updated

5. **User verifies** (Arbitrum Sepolia):
   - Checks balance with `balanceOf()`
   - Confirms interest rate with `getUserInterestRate()`

---

## 📁 Project Structure

```
rebase-token/
├── src/
│   ├── RebaseToken.sol              # Core rebasing ERC20
│   ├── Vault.sol                    # ETH ↔ RBT gateway
│   ├── BurnMintRebaseTokenPool.sol  # CCIP TokenPool override
│   └── interfaces/
│       └── IRebaseToken.sol         # Token interface
├── test/
│   ├── unit/
│   │   └── RebaseTokenUnitTests.t.sol      # Unit tests
│   └── integration/
│       └── CrossChainTest.t.sol            # CCIP integration tests
├── lib/
│   ├── openzeppelin-contracts/      # OZ dependencies
│   ├── chainlink-ccip/              # Chainlink CCIP contracts
│   ├── chainlink-local/             # Chainlink local simulator
│   └── forge-std/                   # Foundry stdlib
├── foundry.toml                     # Foundry configuration
└── README.md                        # This file
```

---

## 🎓 What I Learned

Building this project deepened my understanding of:

1. **Rebasing Mechanisms** — How dynamic balances work and the math behind interest accrual
2. **Cross-Chain Communication** — Chainlink CCIP architecture, TokenPool patterns, message routing
3. **Solidity Advanced Patterns** — Role-based access, function overrides, encoded data passing
4. **Testing Strategies** — Fuzzing, fork testing, cross-chain simulation with Chainlink Local
5. **DeFi Mechanics** — Token economics, rate incentives, early-adopter rewards
6. **Trade-offs in Design** — When to prioritize clarity over complexity, known limitations in demo projects

---

## 🤝 Contributing

This is an educational project. Suggestions for improvements:

- [ ] Implement governance for interest rate changes
- [ ] Add circuit breakers and emergency pausing
- [ ] Support multi-decimal bridging
- [ ] Implement weighted average rates for transfers
- [ ] Add Natspec documentation for all functions
- [ ] Expand to more chains (Polygon, Optimism, Base, etc.)

---

## 📄 License

MIT License — See LICENSE file for details

---

## ⚡ Quick Start Command Reference

```bash
# Install & test
git submodule update --init --recursive && forge test

# Run specific test
forge test --match-contract CrossChainTest -vvv

# Format code
forge fmt

# Lint code
forge lint

# Build
forge build

# Gas analysis
forge test --gas-report
```

---

**Built by**: Nzesi  
**Framework**: Foundry  
**Chains**: Ethereum Sepolia, Arbitrum Sepolia  
**CCIP**: Local fork simulation with CCIPLocalSimulatorFork
