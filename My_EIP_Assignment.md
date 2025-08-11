# EIP-XXXX - Decentralized Random Block Proposal System

## Title: Decentralized Random Block Proposal System
## Description: Proposes a decentralized mechanism for block proposing using shared randomness across Ethereum clients, integrated with Byzantine Fault Tolerance(BFT) for consensus, to eliminate block-level Maximal Extractable Value and mitigate centralization in Proposer-Builder Separation(PBS).
## Author: Victor Akinluyi (@Ayomiposi233, ayomiposi233@gmail.com) & Malik Aremu (@Malik672, aremumalik05@gmail.com)
## Status: Draft
## Type: Standards Track
## Category: Core
## Created: 2025-08-07
## Requires: 4788, 4844, 7251


## Abstract
This EIP introduces a decentralized random block proposal system for Ethereum, shifting block construction from centralized builders under Proposer-Builder Separation (PBS) to a distributed process executed by all Ethereum clients (e.g., Geth, Nethermind). Clients use a shared cryptographically secure random algorithm, seeded by RANDAO and a Verifiable Delay Function (VDF), to select transactions and blobs from local mempools. Validators then execute the proposed blocks, prune invalid elements, and achieve consensus via Byzantine Fault Tolerance (BFT) with a threshold of N ≥ 3T + 1, where N is the total number of validators and T is the number of faulty ones. This eliminates block-level Maximal Extractable Value (MEV), fully democratizes block proposing, enhances propagation speed, and maintains compatibility with Danksharding's rollup-centric future. The system prioritizes trustlessness and decentralization over optimization, addressing the current issue where ~80% of blocks are controlled by two builder entities.

## Motivation
Ethereum's adoption of Proof-of-Stake (PoS) and PBS has mitigated some MEV disparities by separating validators (proposers) from specialized builders. However, centralization persists: As of February 2025, approximately 80% of Ethereum blocks are proposed by just two builder-relay coalitions (e.g., Flashbots and peers), concentrating power, profits, and risks like censorship. MEV—value extracted via transaction reordering or exclusion—remains dominated by sophisticated actors, undermining Ethereum's decentralized ethos.

Existing solutions like PBS redistribute MEV but do not eliminate it at the block level, nor do they address builder centralization. This EIP proposes a radical shift: Empower all Ethereum clients to propose blocks randomly, ensuring no entity can predict or manipulate order. Validators focus on execution and BFT consensus, tolerating up to 33% faults. This aligns with Ethereum's trustless roots, supports scalability via blob integration, and could reduce slot times from 12 seconds to 6-8 seconds through parallel proposals. It is crucial for an Ethereum valuing equity and full democratization over L2-specific optimizations.

## Specification
The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This EIP modifies Ethereum's block production and consensus mechanisms post-Pectra upgrade. It deprecates PBS builders and relays, replacing them with client-side random proposal and validator BFT.

## Parameters 
| Constant | Value | Description |
|----------|-------|-------------|
| `RANDOM_SEED_SOURCE` | RANDAO + VDF | Source for shared randomness. |
| `BFT_THRESHOLD` | N ≥ 3T + 1 | BFT tolerance, where N = total validators, T = faulty (up to 33%). |
| `MIN_AGREEMENT` | 2T + 1 | Minimum validators for majority hash agreement. |
| `MAX_BLOBS_PER_BLOCK` | 16 | Maximum blobs (aligned with Danksharding). |
| `SLOT_TIME_REDUCTION` | 6-8 seconds | Proposed slot time (configurable via chain spec). |
| `REWARD_SUBSET_SIZE` | 10% of agreeing validators | Random subset for rewards to ensure fairness. |

## Core Mechanism
### Block Proposal

Every Ethereum execution client MUST run an identical random selection algorithm to construct a block proposal:
- __Seeding Randomness__: Use the previous block's RANDAO reveal combined with a VDF output from the validator set to generate a verifiable random seed. The VDF ensures unpredictability and prevents front-running.
- __Transaction and Blob Selection__: From the client's local mempool, randomly select transactions and blobs up to gas limits and `MAX_BLOBS_PER_BLOCK`. Use a cryptographically secure pseudo-random number generator (PRNG) seeded by the shared randomness to order and include items. Prioritize high-fee transactions with a weighted randomness (e.g., 70% probability for rollup blobs to balance fairness and L2 efficiency).
- __Output__: Produce a block body with transactions, blobs, and a computed hash.

Pseudocode for selection:
```
def random_block_proposal(mempool, blobs, seed):
    prng = PRNG(seed)  # e.g., ChaCha20 seeded by RANDAO + VDF
    sorted_txs = sort_by_fee(mempool)  # Optional weighting
    selected_txs = []
    selected_blobs = []
    gas_used = 0
    while gas_used < TARGET_GAS_LIMIT and len(selected_txs) < MAX_TXS:
        idx = prng.next() % len(sorted_txs)
        tx = sorted_txs[idx]
        if tx.gas + gas_used <= TARGET_GAS_LIMIT:
            selected_txs.append(tx)
            gas_used += tx.gas
    # Similarly for blobs, up to MAX_BLOBS_PER_BLOCK
    for _ in range(MAX_BLOBS_PER_BLOCK):
        if blobs:
            idx = prng.next() % len(blobs)
            selected_blobs.append(blobs[idx])
    return BlockBody(selected_txs, selected_blobs)
```
Clients MUST broadcast their proposed block to the validator network simultaneously.

### Execution and Consensus

Validators MUST:
- Receive proposals and execute the block (run EVM for transactions, verify blobs).
- Prune invalid elements (e.g., double-spends, invalid signatures).
- Compute a hash of the valid block remainder.
- Broadcast their hash.

Consensus is achieved via BFT:
- Collect hashes; the majority hash (from at least 2T + 1 validators) becomes the canonical block.
- If no majority (due to mempool drift);
    - fallback: Select the most popular proposal or re-randomize from submitted blocks.

### Rewards
From validators agreeing on the winning hash, randomly select a subset (e.g., 10%) for rewards, distributed proportionally to stake. 

### Blob Integration
Clients MUST randomly select blobs alongside transactions, supporting Danksharding. Blobs are included in sidecars, with data availability checks via existing mechanisms (e.g., EIP-4844).

### Network Changes
- Modify P2P protocols to gossip proposals and hashes.
- Update beacon chain specs for BFT voting in slots.

This requires changes to execution clients (e.g., add random proposal module) and consensus clients (e.g., BFT hash voting).

## Rationale
The design uses shared randomness to prevent MEV manipulation, democratizing proposing across thousands of clients instead of two builders. BFT ensures resilience to faults and mempool variance. Alternatives considered:
- Enshrined PBS (ePBS): Retains builders, not fully decentralizing.
- Multiple Concurrent Proposers: Similar parallelism but lacks randomness for MEV suppression.

### Trade-offs
Sacrifices L2 optimization (e.g., no priority for specific blobs) for fairness; mitigated by weighted randomness. Slot time reduction leverages parallel proposals, outpacing PBS flows. Community feedback from ethresear.ch emphasizes trustlessness over efficiency, aligning with Vitalik Buterin's decentralization vision.

## Backwards Compatibility
This EIP introduces breaking changes to PBS:
- Deprecates builder relays; existing builders can run as clients but lose centralized control.
- Validators shift from attesting PBS blocks to BFT voting—requires client upgrades.
- Mempool broadcasting remains compatible, but randomness may delay specific inclusions.
- Mitigation: Phase-in over forks (e.g., optional in Fusaka, mandatory in Glamsterdam). No impact on historical state; transactions from old PBS blocks validate normally.

## Test Cases
Test cases focus on consensus changes:
- __Randomness Consistency__:
    - Input: Identical mempools and seed.
    - Output: All honest clients produce the same block.
- __BFT Tolerance__: Simulate 33% faulty validators; ensure majority hash wins.
- __Mempool Drift__: Vary mempools by 20%; test fallback to most popular proposal.
- __Files__: Provide in `assets/eip-xxxx/tests.json` with input seeds, mempools, expected hashes.

Example:
```
Test Case 1:
Input: Seed = 0xabc..., Mempool = [tx1, tx2, tx3]
Expected: Selected = [tx2, tx1], Hash = 0xdef...
```
## Reference Implementation
See pseudocode in Specification. A prototype in Rust (for Reth client) could integrate as:
```
mod random_proposal {
    fn propose_block(...) -> Block { ... }
}
```
Full reference in a GitHub repo fork of go-ethereum, demonstrating BFT integration.

## Security Considerations
- __MEV Attacks__: Randomness prevents prediction; VDF blunts timing exploits.
- __DDoS Risks__: Spam dilutes mempools but doesn't bias selection; client redundancy mitigates choke points.
- __Fault Tolerance__: BFT handles up to 33% malicious validators (e.g., T=100,000 of N=300,000); exceeds PBS relay risks.
- __Mempool Drift__: If variance > T, consensus fails—mitigated by sync improvements and fallbacks.
    - Bandwidth: Proposals add ~1-2 MB/block load, manageable post-Dencun.
- __Economic Attacks__: Random rewards deter collusion. Encrypted mempools (inspired by SUAVE) could hide transactions until inclusion.

## Copyright
Copyright and related rights waived via CC0 (../LICENSE.md).













