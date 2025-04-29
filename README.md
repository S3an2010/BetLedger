# BetLedger

A decentralized sports betting protocol built on Stacks blockchain using Clarity smart contracts.

## Overview

BetLedger enables trustless sports betting by implementing a fully on-chain betting system. The protocol allows anyone to create betting events for sports matches, set odds for different outcomes, place bets with STX tokens, and automatically distribute winnings when results are verified.

## Features

- **Event Creation**: Create betting events for any sports match or competition
- **Multiple Outcomes**: Set up multiple possible outcomes with customizable odds
- **Secure Betting**: Place bets using STX tokens with full transparency
- **Automated Payouts**: Winners automatically receive their payouts when results are verified
- **Platform Fee**: Sustainable fee structure (default 2.5%) to support protocol development

## Smart Contract Architecture

The core contract (`bet-ledger-core.clar`) implements the following functionality:

- Event management (creation, closing, resolution)
- Outcome definition with odds
- Bet placement and tracking
- Winnings calculation and distribution
- Administrative controls

## Usage

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed for local development
- [Hiro Wallet](https://wallet.hiro.so/) for interacting with the deployed contract

### Local Development

1. Clone the repository
```bash
git clone https://github.com/yourusername/bet-ledger.git
cd bet-ledger
```

2. Test the contract using Clarinet
```bash
clarinet test
clarinet check
```

### Key Functions

#### Creating an Event
```clarity
(contract-call? .bet-ledger-core create-event "World Cup Final" "Soccer" u100000 u110000 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

#### Adding an Outcome
```clarity
(contract-call? .bet-ledger-core add-outcome u0 u0 "Team A Wins" u250)
```

#### Placing a Bet
```clarity
(contract-call? .bet-ledger-core place-bet u0 u0 u1000000)
```

#### Resolving an Event
```clarity
(contract-call? .bet-ledger-core resolve-event u0 u0)
```

#### Claiming Winnings
```clarity
(contract-call? .bet-ledger-core claim-winnings u0)
```

## Data Structures

### Events
```
{
  name: String,
  sport: String,
  start-time: uint,
  end-time: uint,
  status: String, // "active", "closed", "resolved"
  creator: principal,
  oracle: principal
}
```

### Outcomes
```
{
  description: String,
  odds: uint, // e.g., 250 = 2.5x
  status: String // "pending", "won", "lost"
}
```

### Bets
```
{
  event-id: uint,
  outcome-id: uint,
  bettor: principal,
  amount: uint,
  potential-payout: uint,
  status: String // "active", "claimed"
}
```

## Future Development

- Oracle integration for result verification
- Multi-signature verification for large events
- Additional statistical reporting functions
- Frontend application for easy interaction
- Mobile app integration

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.