#!/bin/bash
# =============================================================================
# Maestro Setup Script for Loopa
# =============================================================================
# Installs Maestro and sets up the testing environment.
# 
# Usage: ./setup_maestro.sh
# =============================================================================

set -e

echo "=========================================="
echo " Maestro Setup for Loopa"
echo "=========================================="

# Check for Java 17+
echo "Checking Java version..."
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
    if [ "$JAVA_VERSION" -lt 17 ] 2>/dev/null; then
        echo "⚠ Java $JAVA_VERSION detected, but Maestro requires Java 17+"
        echo "Installing OpenJDK 17 via Homebrew..."
        brew install openjdk@17
        echo 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' >> ~/.zshrc
        export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
    else
        echo "✓ Java $JAVA_VERSION is installed"
    fi
else
    echo "⚠ Java not found. Installing OpenJDK 17 via Homebrew..."
    brew install openjdk@17
    echo 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' >> ~/.zshrc
    export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
fi

# Check if Maestro is already installed
if command -v maestro &> /dev/null; then
    echo "✓ Maestro is already installed"
    maestro --version
elif [ -f "$HOME/.maestro/bin/maestro" ]; then
    echo "✓ Maestro found at ~/.maestro/bin"
    export PATH="$PATH:$HOME/.maestro/bin"
else
    echo "Installing Maestro..."
    curl -Ls "https://get.maestro.mobile.dev" | bash
    
    # Add to PATH for current session
    export PATH="$PATH:$HOME/.maestro/bin"
    
    echo "✓ Maestro installed successfully"
fi

echo ""
echo "=========================================="
echo " Verification"
echo "=========================================="

# Verify installation
if command -v maestro &> /dev/null; then
    echo "Maestro version: $(maestro --version)"
    echo ""
    echo "✓ Setup complete!"
    echo ""
    echo "=========================================="
    echo " Usage"
    echo "=========================================="
    echo ""
    echo "Run a single flow:"
    echo "  maestro test .maestro/record_flow.yaml"
    echo ""
    echo "Run all flows:"
    echo "  maestro test .maestro/"
    echo ""
    echo "Record a new flow:"
    echo "  maestro record"
    echo ""
    echo "View flow in studio:"
    echo "  maestro studio"
    echo ""
else
    echo "Error: Maestro installation failed"
    echo "Try manual installation: https://maestro.mobile.dev/getting-started/installing-maestro"
    exit 1
fi

