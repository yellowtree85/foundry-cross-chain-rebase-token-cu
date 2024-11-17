# Cross-Chain Rebase Token

This project is a cross-chain rebase token that integrates Chainlink CCIP to enable users to bridge their tokens cross-chain

## Project design and assumptions

## NOTES

- assumed rewards are in contract
- Protocol rewards early users and users which bridge to the L2
  - The interest rate decreases linearly with time since the protocol started
  - The interest rate when a user bridges is bridges with them and stays static. So, by bridging you get to keep your high interest rate.
- New interest tokens are only minted to you on the L1 NOT the L2. In order to actually be minted your interest, you have to bridge back to the L1. ACTUALLY this might be fine to be honest!
- You can only deposit and withdraw on the L1.
- You cannot earn interest in the time while bridging.
- If you transfer your tokens to someone on the destination chain(s), they will not earn interest. If they transfer them back to you, you will.

Don't forget to bridge back the amount of interest they accrued on the destination chain in that time
