# Vendored dependencies

- `openzeppelin-contracts` v5.0.2: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
  Archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`. Vendored 6 files.

- `forge-std` v1.9.7: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
  Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`. Vendored 30 files.

OpenZeppelin includes only the ERC-20 import closure and its MIT license.
Forge Standard Library includes its complete src directory and both licenses.
Upstream source files are unmodified. No submodules or package install are needed.
Run `sha256sum -c lib/SHA256SUMS` from the repository root to check the vendored files.
