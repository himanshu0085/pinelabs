#!/usr/bin/env bash
#===============================================================================
# Git Large File Cleaner - Prerequisites Setup
#===============================================================================
# This script automates the installation of all dependencies required for
# the git-large-file-cleaner.sh script.
#
# Requirements:
#   - Ubuntu/Debian-based system
#   - Sudo access
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Check for Sudo
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run with sudo."
   echo "Usage: sudo ./setup-prerequisites.sh"
   exit 1
fi

print_status "Starting prerequisites setup..."

# 2. Install System Packages
print_status "Updating apt and installing system packages (git, bc, python3-pip, awscli)..."
apt-get update -qq
apt-get install -y git bc python3-pip awscli -qq

# 3. Install git-filter-repo
# We install it for the current non-sudo user, or system-wide if preferred.
# The user wants it to work for the current user.
# Since we are running as sudo, we will install it system-wide so it's available in /usr/local/bin
print_status "Installing git-filter-repo system-wide via pip..."
pip3 install git-filter-repo --quiet

# 4. Verify Installations
print_status "Verifying installations..."

if command -v git >/dev/null; then
    print_success "git $(git --version) installed."
else
    print_error "git installation failed."
fi

if command -v bc >/dev/null; then
    print_success "bc installed."
else
    print_error "bc installation failed."
fi

if command -v git-filter-repo >/dev/null; then
    print_success "git-filter-repo installed."
else
    # If not in path, check common local bin
    if [[ -f "/usr/local/bin/git-filter-repo" || -f "/home/$SUDO_USER/.local/bin/git-filter-repo" ]]; then
        print_success "git-filter-repo found but may need PATH update."
    else
        print_error "git-filter-repo installation could not be verified."
    fi
fi

if command -v aws >/dev/null; then
    print_success "AWS CLI $(aws --version | awk '{print $1}') installed."
else
    print_error "AWS CLI installation failed."
fi

# 5. PATH Check for the regular user
USER_HOME=$(eval echo "~$SUDO_USER")
LOCAL_BIN="$USER_HOME/.local/bin"

if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    print_status "Adding $LOCAL_BIN to PATH in .bashrc for $SUDO_USER..."
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$USER_HOME/.bashrc"
    print_success "PATH updated. Please run 'source ~/.bashrc' after this script."
fi

echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}              SETUP COMPLETE!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
echo -e "Next steps:"
echo -e "1. ${YELLOW}aws configure${NC} - Set your S3 access keys."
echo -e "2. ${YELLOW}source ~/.bashrc${NC} - Refresh your terminal PATH."
echo -e "3. ${YELLOW}./git-large-file-cleaner.sh <repos_dir>${NC} - Start scanning!"
echo ""
