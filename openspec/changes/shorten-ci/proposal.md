## Why

A full CI run takes about 20 minutes. The organization shares five macOS runners across all pull requests.

## What changes

Separate checks, reuse verified dependencies, skip macOS for documentation changes, and reject compiler warnings in repository targets.

## Capabilities

### New capabilities
- `ci`: Select checks from changed paths and run independent shards.

### Modified capabilities
None.

## Impact

Developer tooling only. No app behavior, schema, or decision record changes. This work addresses issue #253 without changing production timeout defaults.

## Reference behavior

### Observed in MoneyMoney 2.5.3
Not applicable to CI.

### Decided for Moneten
Target ten minutes elapsed and at most twenty macOS job minutes per full run, with at most four macOS jobs running at once.
