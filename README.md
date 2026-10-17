# Briefs.fun (BRIEFS)

`BriefsToken` is a fixed supply ERC-20. Its constructor mints **1,000,000,000 BRIEFS** with **18 decimals**, entirely to the immediate deploying address (`msg.sender`). The total supply in base units is **1000000000000000000000000000** (`10^27`).

## Contract and assumptions

The deployable contract is [`src/BriefsToken.sol`](src/BriefsToken.sol). It extends the vendored OpenZeppelin Contracts **v5.0.2** ERC-20 without modifying its transfer or allowance logic. `INITIAL_SUPPLY` is the named constant for the single constructor mint.

- Name: `Briefs.fun`; symbol: `BRIEFS`; decimals: `18`.
- Transfers deliver the exact requested amount. There are no token taxes, fees, rebases, or restrictions on nonzero recipients.
- Successful transfers and approvals return `true`; invalid operations revert with OpenZeppelin's ERC-6093 custom errors. Zero-value transfers between nonzero addresses are supported and emit `Transfer`. Self-transfers preserve balances.
- `approve` replaces an allowance. `transferFrom` decreases finite allowances, while `type(uint256).max` remains an unlimited approval. An approval does not move funds. Failed transfers roll back all changes, including allowance spending.
- There is no external mint or burn, owner, role, pause, blacklist, confiscation, upgrade, initializer, or configurable setting. The deployer has no special rights after receiving the initial supply. The supply remains constant.
- There are no constructor arguments, external constructor calls, linked libraries, external runtime calls, or callbacks to recipients. The token uses no oracle, clock, randomness, bridge, or chain-specific precompile.

The brief requests a token without additional transfer rules, so standard ERC-20 behavior is the only behavior added beyond the fixed metadata and supply. No application contracts are needed. Interfaces follow [ERC-20](https://eips.ethereum.org/EIPS/eip-20); the implementation is pinned to the [OpenZeppelin v5.0.2 source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol).

## Build and check

Run from this repository's root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x25f0dc836b0e3f11abe215463ca36f701acd25fa7c4a6b15a9dc7c2bb1862a3a forge test
forge fmt --check
```

[`foundry.toml`](foundry.toml) pins Solidity **0.8.26**, the **Cancun** EVM target, optimizer **200** runs, and `bytecode_hash = "none"`. It sets 1,024 cases per fuzz test and 128 sequences of up to 64 calls per invariant test. No seed is pinned in the configuration; the command above supplies the assignment's seed.

All source dependencies are ordinary files in `lib/`, including their licenses. No dependency download, submodule, RPC connection, wallet, environment configuration file, FFI, or filesystem cheatcode access is required to build or test. The compiler itself is provided by the build environment, not vendored here. See [`lib/DEPENDENCIES.md`](lib/DEPENDENCIES.md) for versions and archive hashes; `sha256sum -c lib/SHA256SUMS` checks the vendored files.

## Tests and review scope

- [`test/BriefsToken.t.sol`](test/BriefsToken.t.sol): metadata, exact initial supply and mint event, immediate deployer semantics, transfer and approval events, zero/self/full-balance transfers, finite and unlimited allowances, revocation, insufficient balances/allowances, zero-address rejection, atomic rollback, and rejection of mint/burn/admin selectors. Four fuzz tests check transfer conservation and failure boundaries.
- [`test/BriefsTokenLaunch.t.sol`](test/BriefsTokenLaunch.t.sol): CREATE2 deployment without arguments, factory custody of the entire initial supply, exact token movements for distribution/claims/pool transfers, runtime size, and the absence of `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT` opcodes.
- [`test/BriefsTokenInvariant.t.sol`](test/BriefsTokenInvariant.t.sol): randomized sequences of transfers, approvals, delegated transfers, and rejected overspending against a separate balance and allowance model. All balances sum to the fixed supply, and all allowances match the model after every step.

Each test constructs isolated state. Tests neither read nor set environment variables, and all fixtures live under `test/`.

The supplied protected tests informed the factory and holder protections. They depend on the separate launch harness, environment, and Uniswap v4 contracts that are not supplied as a runnable project here. The local launch test checks the token side of those movements; it is not a real pool initialization or swap test. The network's independent protected checks remain responsible for that integration.

Local review checks the constructor's only mint path, the public ABI, unchanged ERC-20 accounting, allowance authorization, transaction rollback, runtime size/opcodes, and vendored dependency integrity. Foundry tests and fuzzing are local evidence, not an independent security audit. Slither and Mythril were not run. Independent adversarial review and launch verification remain release responsibilities.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `BriefsToken` |
| Fully qualified artifact | `src/BriefsToken.sol:BriefsToken` |
| Constructor arguments | None (`[]`) |
| Native currency supplied to constructor | None; constructor is nonpayable |
| Initial recipient | Immediate deployer, automatically |
| Name / symbol / decimals | `Briefs.fun` / `BRIEFS` / `18` |
| Total supply in base units | `1000000000000000000000000000` |
| Post-deployment initialization | None |

Creation bytecode and the ABI are available through `forge inspect src/BriefsToken.sol:BriefsToken bytecode` and `forge inspect src/BriefsToken.sol:BriefsToken abi`. Deploy the compiled creation bytecode directly, with no appended arguments. A factory deployment gives the entire supply to the factory, regardless of the transaction origin. A direct deployment gives it to that direct deployer. There is no proxy or initializer step.

The assignment's launch context is Robinhood Chain, **chain ID 4663**. The factory, supplied by the launch system, receives all tokens before performing distribution. The token does not allocate or reserve supply for any address in its constructor beyond the deployer.

The following are launch-system parameters supplied by the brief, not token constructor arguments or settings:

| Launch parameter | Supplied value |
| --- | --- |
| Paired currency | IMD, `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`, 18 decimals |
| Pool fee | `12500` (1.25%, a pool fee; the token charges no transfer fee) |
| Tick spacing | `60` |
| Pool initial-price provenance | `79228162514264337593543950336` |
| Initial market cap in paired-currency base units | `3500000000000000000000` (3,500 IMD) |
| Pool allocation | `poolBps = 8000`, or 800,000,000 BRIEFS |
| Swarm allocation, handled by factory/distributor | 100,000,000 BRIEFS |
| Remainder | 100,000,000 BRIEFS to `0xd6302976e590b9b947da8774b7f1246164e0ce98` |

The launch system derives the actual opening pool price from market capitalization, supply, and token ordering. It owns factory selection, salt selection, distribution, pool initialization, and transactions. The separate manifest step writes `launch.json` after acceptance. This project does not supply a manifest or broadcast transactions.

## After launch

There are **no owner setters or initialization calls**. The launch operator should verify the deployed source/bytecode and metadata, confirm the initial mint to the factory, and verify the factory's distribution and pool setup against the launch terms. The launch operator also handles explorer verification and the independent review required before release.

Wallets and integrations must display 18 decimals and query current allowances directly: this OpenZeppelin version emits `Approval` for `approve`, but not when `transferFrom` consumes an allowance. Holders control their approvals and should grant only the allowance they intend; when replacing an active allowance, revoke it to zero and confirm before granting a new one to reduce the standard ERC-20 allowance race.

No administrator can recover a mistaken transfer or freeze a compromised holder. The contract does not accept ordinary native-currency payments and has no rescue function; tokens sent to the token contract itself, unrelated tokens sent there, or native currency forcibly delivered there cannot be recovered by an administrator.
