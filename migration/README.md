# Git Large File Cleaner - User Guide

This script is designed to safely remove files larger than 100MB from Git history across multiple Bitbucket repositories. It ensures that large files are backed up to AWS S3 before being permanently removed from the Git history using `git-filter-repo`.

## 📋 Prerequisites

Before running the script, ensure your system has the following tools installed:

### 1. Essential Tools
- **Git** (version 2.22 or higher)
- **bash** (Standard on Linux/macOS)
- **bc** (An arbitrary precision calculator language)
- **tar**, **find**, **awk** (Standard Unix utilities)

### 2. Core Dependencies
- **git-filter-repo**: The modern tool for rewriting Git history.
- **AWS CLI**: Required to upload large files to S3.

---

## 🛠️ Installation Instructions

### Step 1: Install Git and Utilities
```bash
sudo apt-get update
sudo apt-get install -y git bc
```

### Step 2: Install git-filter-repo
The recommended way is via `pip`:
```bash
# Install pip if you don't have it
sudo apt-get install -y python3-pip

# Install git-filter-repo
pip3 install git-filter-repo

# Ensure it's in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

### Step 3: Install AWS CLI
If not already installed:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Step 4: Configure AWS Credentials
The script needs permission to upload to your S3 bucket (`ot-gb-migration-large-files`).
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, and Region
```

---

## 🚀 How to Run the Script

The script is located at:
`/home/himanshuparashar/.gemini/antigravity/scratch/git-large-file-cleaner/git-large-file-cleaner.sh`

### 1. Initial Setup
Make the script executable:
```bash
chmod +x git-large-file-cleaner.sh
```

### 2. Run Dry-Run (Safe Preview)
Always run a dry-run first to see which files will be affected. No changes will be made.
```bash
./git-large-file-cleaner.sh <path-to-repos-directory>
```
*Example:* `./git-large-file-cleaner.sh ~/bitbucket-repos`

### 3. Review the Report
The script generates a CSV report in a timestamped output directory:
- **Location**: `~/bitbucket-repos/git-cleaner-output-<timestamp>/large-files-report.csv`
- **Content**: Repo name, file path, size, blob hash, and target S3 path.

### 4. Execute Cleanup (Destructive)
Once you have reviewed the report and are ready to proceed:
```bash
./git-large-file-cleaner.sh <path-to-repos-directory> --execute
```
> [!WARNING]
> This mode will rewrite Git history and force-push to Bitbucket. It will prompt you to type `YES` before starting.

---

## 🛡️ Safety Features
- **Full Backups**: Before any history rewrite, the script creates a `.tar.gz` backup of the entire repository in the `backups/` folder.
- **Dry-Run Default**: The script never executes destructive actions unless `--execute` is explicitly passed.
- **Verification**: After rewriting history, the script automatically verifies that no files larger than 100MB remain in the repository.

---

## 🔍 Manual Verification
After the script finishes, you can manually verify a repository:
```bash
cd <repo-directory>

# 1. List any blobs > 100MB (Should return nothing)
git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize)' | awk '$1 == "blob" && $3 >= 104857600'

# 2. Check S3 for the uploaded files
aws s3 ls s3://ot-gb-migration-large-files/ --recursive

# 3. Check repo integrity
git fsck --full
```

```
find ~/bitbucket-repos -name "large-files-report.csv"
```
