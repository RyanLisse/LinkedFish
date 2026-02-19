# LinkLion / LinkedInKit – just recipe file
# Usage: just [recipe]   e.g. just build, just test, just install

default:
    just build

# Development build
build:
    swift build

# Release build (optimized)
release:
    swift build -c release

# Run all tests
test:
    swift test

# Run tests with verbose output
test-verbose:
    swift test --verbose

# Run a specific test by name (usage: just test-filter "TestName")
test-filter filter:
    swift test --filter "{{filter}}"

# Install CLI and MCP to /usr/local/bin (builds release first)
install: release
    cp .build/release/linkedin /usr/local/bin/
    cp .build/release/linkedin-mcp /usr/local/bin/
    @echo "Installed linkedin and linkedin-mcp to /usr/local/bin"

# Remove build artifacts
clean:
    rm -rf .build

# Resolve/update dependencies
resolve:
    swift package resolve

# Show project structure and available recipes
list:
    just --list
