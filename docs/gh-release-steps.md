# GitHub Release Steps

## 1. Archive & export in Xcode

```
Product → Archive → Distribute App → Copy App
```

Choose "Copy App" (not App Store or notarization). This produces a plain `.app` bundle.

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
