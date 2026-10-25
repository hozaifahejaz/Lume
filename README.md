# Lume

A quiet, minimalist Mac optimiser written in SwiftUI. Four screens, one accent colour, no nagging.

## What it does

- **Overview**: live processor, memory and disk rings, a one-minute processor graph, and the heaviest apps (sort by memory or CPU, hover to quit one).
- **Clean**: measures app caches, logs, Xcode DerivedData and the Trash, then removes the ones you pick after a confirmation.
- **Storage**: the largest folders in your home folder plus Applications, with a jump to Finder.
- **Startup**: launch agents that run at login. Yours can be paused (the file is moved to `~/Library/LaunchAgents (Disabled by Lume)`, so it is fully reversible). System-wide ones are shown read-only.
- **Menu bar**: a small glance at the three numbers.

## Run it

Requires macOS 14 or later and Xcode 15+ (or the Command Line Tools).

```sh
cd Lume
swift run                 # quick run from source
./scripts/build-app.sh    # produces build/Lume.app
open build/Lume.app
```

You can also open `Package.swift` in Xcode and press Run.

## Permissions

The app is not sandboxed, so it can read your Library folders. The Trash and some caches need **Full Disk Access** (System Settings › Privacy & Security). Without it, those rows show a lock and are skipped.

## Design notes

- Rounded light numerals, a single blue accent that warms to orange as a resource fills.
- Cards on a soft secondary background, hairline borders, generous spacing.
- Controls reveal on hover so lists stay calm.
- Follows the system light or dark appearance.
