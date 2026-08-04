# phrase-assembler-rust

Rust final phrase assembler (Milestone 0 skeleton). Collects adjudicated
symbols into the ordered UTF-8 phrase in later milestones.

## Commands

```bash
cargo build                    # build
cargo test                     # unit + integration tests
cargo fmt --check              # format check
cargo clippy --all-targets -- -D warnings   # lint
```

The toolchain is pinned in `rust-toolchain.toml` at the repository root
(1.97.1 with clippy and rustfmt). CI enforces a 90% line-coverage threshold
via cargo-llvm-cov.
