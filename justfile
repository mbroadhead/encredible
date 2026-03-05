# List available recipes
default:
    @just --list

# Run all tests
test:
    ./test/bats/bin/bats test/encredible.bats

# Initialize git submodules
setup:
    git submodule update --init --recursive

# Show current version
version:
    @grep '^VERSION=' bin/encredible | cut -d'"' -f2

# Bump patch version (0.1.0 → 0.1.1)
bump-patch:
    @just _bump patch

# Bump minor version (0.1.0 → 0.2.0)
bump-minor:
    @just _bump minor

# Bump major version (0.1.0 → 1.0.0)
bump-major:
    @just _bump major

_bump part:
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(grep '^VERSION=' bin/encredible | cut -d'"' -f2)
    IFS='.' read -r major minor patch <<< "$current"
    case "{{part}}" in
      patch) patch=$((patch + 1)) ;;
      minor) minor=$((minor + 1)); patch=0 ;;
      major) major=$((major + 1)); minor=0; patch=0 ;;
    esac
    new="${major}.${minor}.${patch}"
    sed -i '' "s/^VERSION=\".*\"/VERSION=\"${new}\"/" bin/encredible
    echo "$current → $new"
