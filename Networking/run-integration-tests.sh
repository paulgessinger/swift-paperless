#!/bin/bash

# run-integration-tests.sh
# Script to run integration tests for the Networking package

set -e

echo "🐳 Starting Paperless-ngx Integration Tests"
echo "==========================================="

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    echo "Please install Docker to run integration tests"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Error: Docker daemon is not running"
    echo "Please start Docker and try again"
    exit 1
fi

echo "✅ Docker is available and running"

# Change to the Networking package directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

echo "📁 Working directory: $PWD"

# Run the tests
echo "🧪 Running integration tests..."
echo ""

# Use swift test with specific test selection if needed
if [ "$#" -eq 0 ]; then
    # Run all integration tests
    swift test --filter "Integration"
else
    # Run specific test if provided
    swift test --filter "$1"
fi

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ All integration tests passed!"
else
    echo ""
    echo "❌ Some integration tests failed (exit code: $exit_code)"
fi

echo "🧹 Integration test run completed"
echo "Note: Docker containers are cleaned up automatically by the test framework"

exit $exit_code