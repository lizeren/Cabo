#!/bin/bash

# Cabo Game Setup Script
# This script helps set up the development environment

echo "Setting up Cabo Game..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for Node.js
if command -v node &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} Node.js found: $(node --version)"
else
    echo -e "${YELLOW}[WARN]${NC} Node.js not found. Please install Node.js for the game server."
fi

# Check for npm
if command -v npm &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} npm found: $(npm --version)"
else
    echo -e "${YELLOW}[WARN]${NC} npm not found. Please install npm for the game server."
fi

# Install server dependencies
echo ""
echo "Installing server dependencies..."
cd Server
npm install
cd ..

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "To run the game server:"
echo "  cd Server && npm start"
echo ""
echo "To build the iOS app:"
echo "  Open CaboGame folder in Xcode and build"
echo ""
echo "Enjoy playing Cabo!"

