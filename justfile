# List available recipes
default:
    @just --list

# Run all tests
test:
    ./test/bats/bin/bats test/encredible.bats

# Initialize git submodules
setup:
    git submodule update --init --recursive
