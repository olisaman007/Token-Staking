# Token Staking Contract

A Clarity smart contract that enables token staking with flexible lock periods and dynamic rewards on the Stacks blockchain.

## Features

- Stake fungible tokens with customizab
- Earn rewards based on stake duration and lock period
- Unstake tokens and claim rewards after lock period ends
- View stake details and estimated rewards
- Community-funded reward pool

  # Functions
  
## Public Functions
- stake-tokens: Stake tokens with a specified lock period
- unstake: Unstake tokens and claim rewards after lock period
- add-to-reward-pool: Add tokens to the community reward pool

  
## Read-Only Functions
- get-stake-details: View details of a specific stake
- get-staker-info: Get information about a staker's positions
- get-total-staked: View total tokens staked in the contract
- get-reward-pool: View current reward pool balance
- get-estimated-reward: Calculate estimated reward for a stake
