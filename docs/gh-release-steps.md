# GitHub Release Steps

## 1. Archive & export in Xcode

```
Product → Archive → Distribute App → Custom → Copy App
```

Choose "Custom", then "Copy App". This produces a plain unsigned `.app` bundle without requiring an Apple Developer account.

## 2. Zip it

```bash
ditto -c -k --keepParent AgentWorkflows.app AgentWorkflows.zip
```

Use `ditto` rather than regular `zip` — it preserves macOS metadata correctly.

## 3. Create a GitHub release

```bash
gh release create v0.1.0 AgentWorkflows.zip \
  --title "AgentWorkflows v0.1.0" \
  --notes "..."
```
