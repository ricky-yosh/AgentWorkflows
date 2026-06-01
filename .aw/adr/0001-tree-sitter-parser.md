# ADR 0001: Use tree-sitter for Code Parsing

## Status

Accepted

## Context

The app needs to parse Swift source code to extract call sequences. The primary alternatives were swift-syntax (Apple's official Swift parser) and tree-sitter (cross-language incremental parser). Swift is the initial language target, but the roadmap includes eventual multi-language support.

swift-syntax is always up-to-date with the Swift language, produces a complete AST, and integrates natively as a Swift Package. However, it is Swift-only — adding any other language would require an entirely separate parser infrastructure.

tree-sitter supports many languages through pluggable grammars, enabling a single parsing pipeline regardless of language. The Swift grammar lags behind swift-syntax in edge-case coverage.

## Decision

Use tree-sitter as the parsing backend.

The tradeoff accepts a slightly less complete Swift grammar today in exchange for a single, extensible parsing architecture that supports multi-language analysis without rework. Swift grammar gaps can be addressed incrementally.

## Consequences

- One parsing pipeline for all current and future languages.
- Multi-language support is additive (add a grammar, not a new parser).
- The Swift grammar may miss some recent language features; these become tracked issues.
- The app must ship or bundle tree-sitter grammars at build time.
