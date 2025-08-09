RETH, an Ethereum execution client written in Rust, implements the Merkle Patricia Trie (MPT) in its `reth_trie` crate as a cryptographically authenticated radix trie for storing key-value bindings, following Ethereum's standard design. However, Reth does not persist the full MPT node structure in the database. Instead, it uses a flat key-value storage for state data and computes the trie root on demand using an optimized hash builder. This approach reduces storage overhead and enables efficient incremental updates.

## Mapping the Merkle Trie to a Key-Value Database
Reth's database (using MDBX as the backend) stores Ethereum state in flat tables rather than as serialized trie nodes. The primary tables for state include:

- __HashedAccount__: Maps keccak-hashed account addresses to RLP-encoded account data (balance, nonce, code hash, storage root).
   - Key: `keccak(address) (32 bytes)`.
   - Value: `RLP([nonce, balance, storage_root, code_hash])`.

- __HashedStorage__: Maps hashed contract storage slots.
   - Key: `keccak(address) + keccak(slot) (64 bytes)`.
   - Value: `keccak(value)` (hashed to save space, as full values are in plain state tables for quick access).

- __PlainAccountState__ and __PlainStorageState__: Unhashed versions for faster lookups during execution `(address -> account, address + slot -> value)`.
- __AccountHistory__ and __StorageHistory__: Sharded indices for historical state changes, used for pruning and queries.

The abstract MPT is mapped to this KV store via hashed keys, where leaves are the state entries (accounts/storage slots) and branches/extensions are computed dynamically. Trie nodes are not stored directly; instead, Reth stores "intermediate hashes" in the database (via `StoredNibbles`, `StoredNibblesSubKey`, and `StoredSubNode` structures) to support incremental root calculations without rebuilding the entire trie from scratch each time. This is key for performance during block execution and validation.

The trie root (state root in block headers) is computed using the `HashBuilder` in `reth_trie`, which sorts hashed state updates (from `HashedPostState` and `HashedStorage`) and builds an in-memory representation of the MPT branches. Here's a simplified breakdown of the process, based on Reth's trie implementation:

- __Key Encoding__: Keys are nibble-encoded (4-bit hex digits) for radix-16 branching. For example, an address is hashed to 32 bytes (64 nibbles), and paths are traversed nibble-by-nibble.

- __Node Types__: Reth defines MPT nodes as enums (TrieNode):
    - Branch: Up to 16 child pointers + value.
    - Extension: Compressed path prefix + child key.
    - Leaf: Terminal key suffix + value.

- __Database Interaction__: During computation, the hash builder fetches sorted state from the flat KV tables, iterates over prefix sets of changed keys, and uses keccak hashing for node hashes. Intermediate branch hashes are cached in DB for future incremental updates (e.g., via `IntermediateStateRootState`).

Pseudo-code for state root computation (derived from Reth's `HashBuilder` logic):

```rust
struct HashBuilder {
    // Sorted hashed state updates
    post_state: HashedPostState,
    // Cursor for DB-fetched intermediate hashes
    cursor: HashedCursor,
}

impl HashBuilder {
    fn compute_root(&mut self) -> B256 {
        let mut stack: Vec<B256> = vec![];
        // Sort keys and iterate in trie order
        for (hashed_key, value) in self.post_state.sorted() {
            let nibbles = Nibbles::from(hashed_key);
            // Traverse nibbles, building branches/extensions
            while let Some(prefix) = common_prefix(&nibbles) {
                // Fetch or compute intermediate hash from DB
                let intermediate = self.cursor.seek(prefix).unwrap_or_default();
                stack.push(keccak(rlp(intermediate)));
            }
            // Add leaf
            stack.push(keccak(rlp([nibbles.suffix(), value])));
        }
        // Reduce stack to root via merkle hashing
        while stack.len() > 1 {
            let a = stack.pop().unwrap();
            let b = stack.pop().unwrap();
            stack.push(keccak(rlp([a, b])));
        }
        stack[0]
    }
}
```

This avoids storing full trie nodes (which would bloat the DB) by leveraging flat state and cached intermediates. Changes are batched in `TrieUpdates` and applied atomically after root verification.

## Handling State Pruning and Storage Optimization

Reth supports configurable pruning to optimize storage by removing historical data while maintaining a full or archive node. Pruning runs periodically (e.g., every 5 blocks by default) and targets tables like history indices, receipts, and transaction senders. It keeps the latest state intact but deletes old entries to reduce DB size (e.g., a full node might use ~1TB vs. 10TB for archive).

- __Types of Pruning__:
    - Distance-Based: Prune data older than a block distance (e.g., keep last 90,000 blocks ~2 weeks on Ethereum).
    - Target-Based: Prune to a specific block or timestamp.
    - Segmented: Separate configs for receipts, transaction history, account history, storage history, and senders.
    - Full Pruning: Enabled with --full flag, automatically prunes all non-essential history.

- __Configuration Options__:
    - CLI: `reth node --prune.full` or `--prune.history.distance=90000 --prune.receipts.distance=90000`.
    - TOML: In `reth.toml`:
```
[prune]
full = true
parts = [
  { sender = "full" },
  { transaction_lookup = "full" },
  { receipts = { variant = "distance", distance = 90000 } },
  { account_history = { variant = "distance", distance = 90000 } },
  { storage_history = { variant = "distance", distance = 90000 } },
]
```
  This prunes senders/transactions fully, and history/receipts beyond 90,000 blocks.

- __Impact on DB Size and Performance__:
    - Reduces size by 50-80% for full nodes (e.g., from archive's 10TB+ to ~1-2TB).
    - Improves query performance by shrinking indices but limits historical queries (e.g., no eth_getBalance at old blocks).
    - Pruning runs in background, using DB compaction to reclaim space. For optimization, Reth uses MDBX's spill-less mode and sharding for history tables to avoid large deletions.

Pruning is handled in the `Pruner` component, which scans tables and deletes entries below the prune target during unwind/rewind stages.

## EIPs in Cancun Affecting State and Database, with Code Breakdowns

The Cancun upgrade (part of Dencun, activated March 2024) includes EIPs that modify state handling. Reth implements these via its EVM integration with revm (Rust EVM) and post-execution hooks. Focus on state/DB-impacting EIPs: EIP-1153 (transient storage), EIP-4788 (beacon root in state), EIP-6780 (SELFDESTRUCT changes). Other EIPs like EIP-4844 affect blobs (temporary DB storage, pruned after ~18 days), but less directly on state trie.

- __EIP-1153: Transient Storage Opcodes (TLOAD, TSTORE)__

Introduces non-persistent storage per transaction (cleared at tx end), for efficient inter-contract communication without gas refunds/refunds issues. Affects state by adding a separate map in EVM memory, not written to persistent DB.
In Reth/revm, added to EVM state as a per-address map. Pseudo-code from revm's opcode handler:

```rust
fn tstore(&mut self, key: U256, value: U256) {
  let address = self.context.address;
  self.transient_storage.insert(address, key, value);
  self.gas.record_cost(100);  // Base gas
}

fn tload(&mut self, key: U256) -> U256 {
  let address = self.context.address;
  self.transient_storage.get(address, key).unwrap_or(U256::ZERO)
}

// At tx end (in post_execute):
self.transient_storage.clear();
```

  This map is in-memory only, optimizing DB writes by avoiding persistent storage slots.

- __EIP-4788: Beacon Block Root in State__

Stores the parent beacon block root in EVM state at address `0x0BEACON_ROOTS_ADDRESS` (predefined contract), in slot `timestamp % HISTORY_BUFFER_LENGTH`. Affects DB by requiring state updates post-block, impacting the state trie root. Used for bridging consensus/execution layers.
In Reth, implemented in post-block execution (not pure EVM, so in reth-node). Pseudo-code from execution stage:

```rust
fn post_block_cancun(&mut self, block: &Block) {
  if chain_spec.is_cancun_active(block.timestamp) {
    let beacon_root = block.parent_beacon_block_root.unwrap();
    let timestamp = block.timestamp;
    let slot = timestamp % HISTORY_BUFFER_LENGTH;
    let address = BEACON_ROOTS_ADDRESS;
    // Update storage slot in state
    self.state.set_storage(address, slot, beacon_root.into());
    // Commit to trie and DB
    self.compute_state_root();
  }
}
```
This adds one storage write per block, optimized by batching in trie updates.

- __EIP-6780: SELFDESTRUCT Only in Same Transaction__

Restricts SELFDESTRUCT: Destroys contract only if created in the same tx; otherwise, just sends balance (no code/storage clear). Affects state by reducing destructive changes, optimizing DB for fewer deletions.
In revm, modified opcode handler:

```rust
fn selfdestruct(&mut self, beneficiary: Address) {
  let address = self.context.address;
  if self.tx.created_contracts.contains(&address) {  // Same tx check
    // Full destroy: clear code, storage, balance
    self.state.clear_storage(address);
    self.state.set_code(address, Bytecode::default());
    self.state.transfer_balance(address, beneficiary, self.state.balance(address));
    self.state.mark_delete(address);
  } else {
    // Only transfer balance
    self.state.transfer_balance(address, beneficiary, self.state.balance(address));
  }
  self.gas.record_cost(5000 + if cold { 2600 } else { 0 });
}
```
This minimizes state trie changes, as storage pruning is avoided unless same-tx creation.

These EIPs are activated via chain spec checks (e.g., `if chain_spec.is_cancun_active_at_timestamp(block.timestamp)`). Reth's implementation ensures backward compatibility and efficient DB commits.

