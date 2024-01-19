# <img src="logo.png" alt="Blueberry" height="128px">

# Blueberry Deployments

This package contains the addresses and ABIs of all of Blueberry's deployed contracts for supported chains, as well as various test networks. Each deployment consists of a deployment script (called 'task'), inputs (script configuration, such as dependencies), outputs (typically contract addresses), ABIs and bytecode files of related contracts.

## Overview

### Deploying Contracts

For more information on how to create new deployments or run existing ones in new networks, head to the [deployment guide](DEPLOYING.md).

## Active Deployments

| Description                                         | Task ID                                                                |
| --------------------------------------------------- | ---------------------------------------------------------------------- |
| Aura Spell - Strategy for Aura                      | [`20240118-aura-spell`](./tasks/20240118-authorizer)                   |
| Convex Spell - Strategy for Convex                  | [`20240118-convex-spell`](./tasks/20240118-vault)                      |
| Blueberry Bank - Manages Positions                  | [`20240118-blueberry-bank`](./tasks/20240118-wsteth-rate-provider)     |
| ShortLong Spell - Short and long strategy           | [`20240118-short-long-spell`](./tasks/20240118-no-protocol-fee-lbp)    |
| Escrow Factory - Deploys new escrows for strategies | [`20240118-escrow-factory`](./tasks/20240118-authorizer-adaptor)       |
| WAura Booster - Helps manage Aura positions         | [`20240118-wAura-booster`](./tasks/20240118-bal-token-holder-factory)  |
| WConvex Booster - Helps manage Convex positions     | [`20240118-wConvex-booster`](./tasks/20240118-balancer-token-admin)    |
| Ichi Spell - Strategy for Ichi                      | [`20240118-ichi-spell`](./tasks/20240118-gauge-controller)             |
| Curve Stable Oracle - Oracle for Curve Stables      | [`20240118-curve-stable-oracle`](./tasks/20240118-test-balancer-token) |
| Protocol Config - Manages global configuration      | [`20240118-protocol-config`](./tasks/20240118-ve-delegation)           |
| Fee Manager - Manages Blueberry's fees              | [`20240118-fee-manager`](./tasks/20240118-child-chain-gauge-factory)   |
