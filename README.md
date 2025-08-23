# 📊 PortFolio - Decentralized Portfolio Tracker

A Clarity smart contract that provides on-chain portfolio tracking for Stacks-based assets with verifiable, transparent records.

## 🚀 Features

- **📈 Asset Tracking**: Add and manage multiple assets in your portfolio
- **💰 Value Calculation**: Track average purchase prices and current values
- **📋 Transaction History**: Complete on-chain transaction records
- **🔐 Privacy Controls**: Grant/revoke viewing permissions to other users
- **⚡ Real-time Updates**: Update asset prices and portfolio values
- **📊 Platform Analytics**: View platform-wide statistics

## 🏗️ Contract Overview

The PortFolio contract manages user portfolios through several key data structures:
- User portfolios with metadata and total values
- Individual asset holdings with price tracking
- Complete transaction history
- Permission system for portfolio sharing
- Platform-wide statistics and fee management

## 📖 Usage Instructions

### 🎯 Initialize Your Portfolio

```clarity
(contract-call? .PortFolio initialize-portfolio)
```

### ➕ Add an Asset

```clarity
(contract-call? .PortFolio add-asset "STX" "STX" u1000 u150)
```
Parameters: `asset-id` `symbol` `amount` `price-in-cents`

### ➖ Remove an Asset

```clarity
(contract-call? .PortFolio remove-asset "STX" u500)
```
Parameters: `asset-id` `amount`

### 💲 Update Asset Price

```clarity
(contract-call? .PortFolio update-asset-price "STX" u175)
```
Parameters: `asset-id` `new-price-in-cents`

### 👀 Grant View Permission

```clarity
(contract-call? .PortFolio grant-view-permission 'SP1234567890 (some u1000))
```
Parameters: `viewer-principal` `optional-expiry-block`

### 🚫 Revoke View Permission

```clarity
(contract-call? .PortFolio revoke-view-permission 'SP1234567890)
```

## 🔍 Read-Only Functions

### Get Portfolio Overview

```clarity
(contract-call? .PortFolio get-portfolio 'SP1234567890)
```

### Get Specific Asset

```clarity
(contract-call? .PortFolio get-user-asset 'SP1234567890 "STX")
```

### Get Transaction

```clarity
(contract-call? .PortFolio get-transaction 'SP1234567890 u1)
```

### Get Transaction Count

```clarity
(contract-call? .PortFolio get-transaction-count 'SP1234567890)
```

### Get Platform Statistics

```clarity
(contract-call? .PortFolio get-platform-stats)
```

## 🛡️ Security Features

- **Owner-only functions**: Platform fee management restricted to contract owner
- **Permission system**: Users control who can view their portfolios  
- **Input validation**: All amounts and prices must be greater than zero
- **Authorization checks**: Functions verify user permissions before execution

## 🏃 Getting Started

1. **Deploy the contract** using Clarinet
2. **Initialize your portfolio** with `initialize-portfolio`
3. **Add assets** to start tracking your holdings
4. **Update prices** as market values change
5. **Share portfolios** by granting view permissions

## 🧪 Development

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity smart contracts

### Testing
```bash
clarinet check
clarinet test
```

### Deployment
```bash
clarinet deploy
```

## 📊 Data Structures

### Portfolio Structure
```clarity
{
  created-at: uint,
  last-updated: uint,
  total-value: uint,
  asset-count: uint
}
```

### Asset Structure
```clarity
{
  symbol: (string-ascii 16),
  amount: uint,
  avg-price: uint,
  last-price: uint,
  added-at: uint,
  updated-at: uint
}
```

### Transaction Structure
```clarity
{
  asset-id: (string-ascii 64),
  action: (string-ascii 8),
  amount: uint,
  price: uint,
  timestamp: uint,
  block-height: uint
}
```

## 🔐 Error Codes

- `u100`: Owner only operation
- `u101`: Resource not found
- `u102`: Invalid amount/price
- `u103`: Resource already exists
- `u104`: Unauthorized access
- `u105`: Invalid asset

## 🎯 Future Enhancements

- 📈 Price oracles integration
- 🔄 Automated rebalancing suggestions  
- 📱 Mobile-friendly portfolio views
- 🏆 Portfolio performance metrics
- 🤝 Social portfolio sharing features

---

**Built with ❤️ using Clarity and Stacks blockchain**
