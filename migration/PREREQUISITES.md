# Environment Setup Guide: Git Large File Cleaner

This document provides the exact commands required to prepare a fresh Linux machine (Ubuntu/Debian) to run the `git-large-file-cleaner.sh` script.

Follow these steps in order to ensure the script has all necessary dependencies and environment settings.

---

## 1. Quick One-Line Setup
If you are on Ubuntu/Debian, you can run this single command to install everything (requires sudo):
```bash
sudo apt-get update && sudo apt-get install -y git python3-pip bc awscli && pip3 install git-filter-repo && export PATH="$HOME/.local/bin:$PATH" && echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

---

## 2. Step-by-Step Installation

### A. System Utilities
The script uses `bc` for calculations and `git` for history management.
```bash
sudo apt-get update
sudo apt-get install -y git bc
```

### B. Python and git-filter-repo
`git-filter-repo` is a Python-based tool. You must install `pip` first, then the tool itself.
```bash
# Install Python package manager
sudo apt-get install -y python3-pip

# Install the history rewrite tool
pip3 install git-filter-repo
```

### C. PATH Configuration (CRITICAL)
When installed via `pip`, `git-filter-repo` is placed in `~/.local/bin`. This directory is often **not** in the system PATH, which will cause the script to fail.
```bash
# Add to current session
export PATH="$HOME/.local/bin:$PATH"

# Make it permanent for future sessions
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

### D. AWS CLI and Credentials
The script needs the AWS CLI to upload files to S3.
```bash
# Install AWS CLI
sudo apt-get install -y awscli

# Configure your access keys (Interactively)
aws configure
```

---

## 3. Pre-Run Checklist
Run these commands to verify everything is ready:

| Command | Expected Output |
|---------|-----------------|
| `git --version` | `git version 2.22` or higher |
| `git-filter-repo --version` | A version string (e.g., `a40bce...`) |
| `aws s3 ls s3://ot-gb-migration-large-files` | List of items or empty (no access errors) |
| `bc --version` | `bc 1.07.1` or similar |

---

## 4. Common Troubleshooting
- **"git-filter-repo: command not found"**: This means the **PATH Configuration** (Step 2C) was missed. Run `export PATH="$HOME/.local/bin:$PATH"`.
- **"pip: command not found"**: Use `pip3` instead of `pip`, or install it via `sudo apt install python3-pip`.
- **"Access Denied (S3)"**: Run `aws configure` again and ensure your IAM user has `s3:PutObject` and `s3:ListBucket` permissions for `ot-gb-migration-large-files`.
