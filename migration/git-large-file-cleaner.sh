#!/usr/bin/env bash
#===============================================================================
# Git Large File Cleaner
#===============================================================================
# A production-ready script to remove large files (>100MB) from Git history
# across multiple repositories without using Git LFS.
#
# Features:
#   - Dry-run mode (default): Preview changes without modifying repos
#   - Execution mode: Requires --execute flag
#   - Batch processing: Handles all repos under a parent directory
#   - CSV reporting: Generates detailed mapping of large files
#   - S3 upload: Backs up large files before removal
#   - Safe history rewrite: Uses git-filter-repo
#   - Full backup: Creates repo backup before modifications
#   - Verification: Confirms cleanup success
#
# Usage:
#   ./git-large-file-cleaner.sh /path/to/repos              # Dry-run
#   ./git-large-file-cleaner.sh /path/to/repos --execute    # Execute
#
# Author: DevOps Engineering Team
# Version: 1.0.0
#===============================================================================

set -euo pipefail

# Ensure ~/.local/bin is in PATH (for pip-installed tools like git-filter-repo)
export PATH="$HOME/.local/bin:$PATH"

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
readonly VERSION="1.0.0"
readonly SCRIPT_NAME=$(basename "$0")
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Defaults
DEFAULT_SIZE_MB=100
DEFAULT_BUCKET="ot-gb-migration-large-files"
DEFAULT_REMOTE="origin"

# Runtime variables
SIZE_THRESHOLD_MB=$DEFAULT_SIZE_MB
SIZE_THRESHOLD_BYTES=$((SIZE_THRESHOLD_MB * 1024 * 1024))
S3_BUCKET=$DEFAULT_BUCKET
GIT_REMOTE=$DEFAULT_REMOTE
EXECUTE_MODE=false
SKIP_S3=false
SKIP_PUSH=false
PARENT_DIR=""

# Output directories (set after PARENT_DIR is known)
OUTPUT_DIR=""
BACKUP_DIR=""
LOG_DIR=""
REPORT_FILE=""

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
    [[ -n "${LOG_FILE:-}" ]] && echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE" || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
    [[ -n "${LOG_FILE:-}" ]] && echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE" || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    [[ -n "${LOG_FILE:-}" ]] && echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE" || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    [[ -n "${LOG_FILE:-}" ]] && echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE" || true
}

log_header() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}" >&2
    echo -e "${BOLD}${CYAN}  $1${NC}" >&2
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}\n" >&2
}

log_subheader() {
    echo -e "\n${BOLD}── $1 ──${NC}\n" >&2
}

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------
format_size() {
    local bytes=$1
    if ((bytes >= 1073741824)); then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif ((bytes >= 1048576)); then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif ((bytes >= 1024)); then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$bytes bytes"
    fi
}

check_dependencies() {
    log_subheader "Checking Dependencies"
    
    local missing=()
    
    # Check git
    if ! command -v git &> /dev/null; then
        missing+=("git")
    else
        log_info "git: $(git --version)"
    fi
    
    # Check git-filter-repo
    if ! command -v git-filter-repo &> /dev/null; then
        missing+=("git-filter-repo")
    else
        log_info "git-filter-repo: installed"
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    else
        log_info "aws-cli: $(aws --version 2>&1 | head -1)"
    fi
    
    # Check other tools
    for cmd in find awk tar bc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Installation instructions:"
        echo "  git-filter-repo: pip install git-filter-repo"
        echo "  aws-cli: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    
    log_success "All dependencies satisfied"
}

show_help() {
    cat << EOF
${BOLD}Git Large File Cleaner v${VERSION}${NC}

Remove files larger than a specified size from Git history across multiple repositories.

${BOLD}USAGE:${NC}
    $SCRIPT_NAME <parent-directory> [OPTIONS]

${BOLD}ARGUMENTS:${NC}
    <parent-directory>    Directory containing Git repositories to process

${BOLD}OPTIONS:${NC}
    --execute             Run in execution mode (default is dry-run)
    --size <MB>           Size threshold in MB (default: ${DEFAULT_SIZE_MB})
    --bucket <name>       S3 bucket name (default: ${DEFAULT_BUCKET})
    --remote <name>       Git remote name (default: ${DEFAULT_REMOTE})
    --skip-s3             Skip uploading files to S3
    --skip-push           Skip force-pushing after rewrite
    -h, --help            Show this help message
    -v, --version         Show version

${BOLD}EXAMPLES:${NC}
    # Dry-run (preview only)
    $SCRIPT_NAME /path/to/repos

    # Execute with default settings
    $SCRIPT_NAME /path/to/repos --execute

    # Custom size threshold (50MB)
    $SCRIPT_NAME /path/to/repos --size 50 --execute

    # Skip S3 upload
    $SCRIPT_NAME /path/to/repos --skip-s3 --execute

${BOLD}OUTPUT FILES:${NC}
    ./git-cleaner-output-<timestamp>/
    ├── large-files-report.csv    # Mapping of all large files
    ├── backups/                  # Repository backups (execute mode)
    └── logs/                     # Detailed operation logs

${BOLD}CSV REPORT COLUMNS:${NC}
    repo-name, file-name, file-size, blob-hash, commit-hash, s3-path

${BOLD}SAFETY:${NC}
    - Dry-run is the default mode
    - Execution mode requires explicit --execute flag
    - Full repository backup created before modifications
    - Confirmation prompt before destructive operations

EOF
}

#-------------------------------------------------------------------------------
# Repository Discovery
#-------------------------------------------------------------------------------
find_git_repos() {
    local parent_dir="$1"
    local repos=()
    
    log_subheader "Discovering Git Repositories"
    
    while IFS= read -r -d '' git_dir; do
        local repo_dir=$(dirname "$git_dir")
        repos+=("$repo_dir")
        log_info "Found: $(basename "$repo_dir")"
    done < <(find "$parent_dir" -maxdepth 2 -type d -name ".git" -print0 2>/dev/null)
    
    if [[ ${#repos[@]} -eq 0 ]]; then
        log_warning "No Git repositories found in: $parent_dir"
        return 1
    fi
    
    log_success "Found ${#repos[@]} repositories"
    printf '%s\n' "${repos[@]}"
}

#-------------------------------------------------------------------------------
# Large File Scanning
#-------------------------------------------------------------------------------
scan_working_directory() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    log_info "Scanning working directory: $repo_name"
    
    find "$repo_dir" -type f -size +"${SIZE_THRESHOLD_MB}M" \
        ! -path "*/.git/*" \
        -exec stat --format="%s %n" {} \; 2>/dev/null | \
    while read -r size filepath; do
        local filename=$(basename "$filepath")
        local relpath=${filepath#$repo_dir/}
        echo "WORKING|$repo_name|$relpath|$size|N/A|N/A"
    done
}

scan_git_history() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    log_info "Scanning Git history: $repo_name"
    
    cd "$repo_dir"
    
    # Get all objects with their sizes
    # Format: blob <hash> <size> <path>
    git rev-list --objects --all 2>/dev/null | \
    git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' 2>/dev/null | \
    awk -v threshold="$SIZE_THRESHOLD_BYTES" -v repo="$repo_name" '
        $1 == "blob" && $3 >= threshold {
            blob_hash = $2
            size = $3
            # Rest is the file path
            path = ""
            for (i = 4; i <= NF; i++) {
                path = path (path ? " " : "") $i
            }
            if (path != "") {
                print "HISTORY|" repo "|" path "|" size "|" blob_hash
            }
        }
    ' | sort -u | \
    while IFS='|' read -r type repo path size blob_hash; do
        # Find commits containing this blob
        local commits=$(git log --all --find-object="$blob_hash" --format="%H" 2>/dev/null | head -5 | tr '\n' ';' | sed 's/;$//')
        if [[ -n "$commits" ]]; then
            echo "HISTORY|$repo|$path|$size|$blob_hash|$commits"
        fi
    done
}

scan_repository() {
    local repo_dir="$1"
    local temp_file=$(mktemp)
    
    # Scan working directory
    scan_working_directory "$repo_dir" > "$temp_file.working" 2>/dev/null || true
    
    # Scan git history
    scan_git_history "$repo_dir" > "$temp_file.history" 2>/dev/null || true
    
    # Combine results
    cat "$temp_file.working" "$temp_file.history" 2>/dev/null | sort -u
    
    # Cleanup
    rm -f "$temp_file.working" "$temp_file.history" "$temp_file"
}

#-------------------------------------------------------------------------------
# CSV Report Generation
#-------------------------------------------------------------------------------
generate_csv_report() {
    local repos=("$@")
    
    log_subheader "Generating CSV Report"
    
    # Write header
    echo "repo-name,file-name,file-size,file-size-human,blob-hash,commit-hash,s3-path" > "$REPORT_FILE"
    
    local total_files=0
    local total_size=0
    
    for repo_dir in "${repos[@]}"; do
        local repo_name=$(basename "$repo_dir")
        
        while IFS='|' read -r type repo filepath size blob_hash commits; do
            [[ -z "$filepath" ]] && continue
            
            local filename=$(basename "$filepath")
            local size_human=$(format_size "$size")
            local first_commit=$(echo "$commits" | cut -d';' -f1)
            local s3_path="s3://${S3_BUCKET}/${repo_name}/${first_commit}/${filename}"
            
            echo "\"$repo_name\",\"$filepath\",\"$size\",\"$size_human\",\"$blob_hash\",\"$commits\",\"$s3_path\"" >> "$REPORT_FILE"
            
            ((total_files++)) || true
            ((total_size += size)) || true
        done < <(scan_repository "$repo_dir")
    done
    
    log_success "Report generated: $REPORT_FILE"
    log_info "Total large files found: $total_files"
    log_info "Total size: $(format_size $total_size)"
    
    echo "$total_files"
}

#-------------------------------------------------------------------------------
# Display Preview (Dry-Run)
#-------------------------------------------------------------------------------
display_preview() {
    log_header "DRY-RUN PREVIEW"
    
    echo -e "${YELLOW}The following files exceed ${SIZE_THRESHOLD_MB}MB and would be processed:${NC}\n"
    
    if [[ ! -f "$REPORT_FILE" ]]; then
        log_error "Report file not found"
        return 1
    fi
    
    # Display table header
    printf "${BOLD}%-30s %-40s %-12s %-10s${NC}\n" "REPOSITORY" "FILE PATH" "SIZE" "COMMITS"
    printf "%s\n" "$(printf '=%.0s' {1..95})"
    
    # Read and display report (skip header)
    tail -n +2 "$REPORT_FILE" | while IFS=',' read -r repo filepath size size_human blob commits s3path; do
        # Remove quotes
        repo=$(echo "$repo" | tr -d '"')
        filepath=$(echo "$filepath" | tr -d '"')
        size_human=$(echo "$size_human" | tr -d '"')
        commits=$(echo "$commits" | tr -d '"')
        
        # Truncate long paths
        if [[ ${#filepath} -gt 38 ]]; then
            filepath="...${filepath: -35}"
        fi
        
        # Count commits
        local commit_count=$(echo "$commits" | tr ';' '\n' | wc -l)
        
        printf "%-30s %-40s %-12s %-10s\n" "$repo" "$filepath" "$size_human" "$commit_count commit(s)"
    done
    
    echo ""
    printf "%s\n" "$(printf '=%.0s' {1..95})"
    
    local file_count=$(tail -n +2 "$REPORT_FILE" | wc -l)
    echo -e "\n${BOLD}Summary:${NC}"
    echo -e "  Total files to process: ${CYAN}$file_count${NC}"
    echo -e "  Report saved to: ${CYAN}$REPORT_FILE${NC}"
    
    echo -e "\n${YELLOW}To execute these changes, run with --execute flag:${NC}"
    echo -e "  $SCRIPT_NAME $PARENT_DIR --execute\n"
}

#-------------------------------------------------------------------------------
# S3 Upload
#-------------------------------------------------------------------------------
upload_file_to_s3() {
    local repo_dir="$1"
    local blob_hash="$2"
    local commit_hash="$3"
    local filename="$4"
    local repo_name=$(basename "$repo_dir")
    
    local s3_path="s3://${S3_BUCKET}/${repo_name}/${commit_hash}/${filename}"
    local temp_file=$(mktemp)
    
    cd "$repo_dir"
    
    # Extract file content from git
    if git cat-file -p "$blob_hash" > "$temp_file" 2>/dev/null; then
        # Upload to S3
        if aws s3 cp "$temp_file" "$s3_path" --quiet 2>/dev/null; then
            log_success "Uploaded: $s3_path"
            rm -f "$temp_file"
            return 0
        else
            log_error "Failed to upload: $s3_path"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_error "Failed to extract blob: $blob_hash"
        rm -f "$temp_file"
        return 1
    fi
}

upload_large_files_to_s3() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    log_subheader "Uploading Large Files to S3: $repo_name"
    
    if [[ "$SKIP_S3" == true ]]; then
        log_warning "S3 upload skipped (--skip-s3 flag)"
        return 0
    fi
    
    local upload_count=0
    local fail_count=0
    
    # Read from report for this repo
    # Use process substitution instead of pipe to avoid subshell scope issues with counters
    while IFS=',' read -r repo filepath size size_human blob commits s3path; do
        # Remove quotes
        blob=$(echo "$blob" | tr -d '"')
        commits=$(echo "$commits" | tr -d '"')
        filepath=$(echo "$filepath" | tr -d '"')
        
        [[ "$blob" == "N/A" ]] && continue
        [[ -z "$blob" ]] && continue
        
        local filename=$(basename "$filepath")
        local first_commit=$(echo "$commits" | cut -d';' -f1)
        
        if upload_file_to_s3 "$repo_dir" "$blob" "$first_commit" "$filename"; then
            ((upload_count++)) || true
        else
            ((fail_count++)) || true
        fi
    done < <(tail -n +2 "$REPORT_FILE" | grep "^\"$repo_name\"")
    
    log_info "Uploaded $upload_count files, $fail_count failures"
}

#-------------------------------------------------------------------------------
# Repository Backup
#-------------------------------------------------------------------------------
create_backup() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    local backup_file="${BACKUP_DIR}/${repo_name}-${TIMESTAMP}.tar.gz"
    
    log_subheader "Creating Backup: $repo_name"
    
    if tar -czf "$backup_file" -C "$(dirname "$repo_dir")" "$repo_name" 2>/dev/null; then
        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Backup created: $backup_file ($backup_size)"
        return 0
    else
        log_error "Failed to create backup for: $repo_name"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# History Rewrite
#-------------------------------------------------------------------------------
collect_paths_to_remove() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    # Extract unique file paths from report
    tail -n +2 "$REPORT_FILE" | grep "^\"$repo_name\"" | \
    while IFS=',' read -r repo filepath rest; do
        filepath=$(echo "$filepath" | tr -d '"')
        echo "$filepath"
    done | sort -u
}

rewrite_history() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    log_subheader "Rewriting History: $repo_name"
    
    cd "$repo_dir"
    
    # Collect paths to remove
    local paths_file=$(mktemp)
    collect_paths_to_remove "$repo_dir" > "$paths_file"
    
    local path_count=$(wc -l < "$paths_file")
    
    if [[ $path_count -eq 0 ]]; then
        log_warning "No files to remove from: $repo_name"
        rm -f "$paths_file"
        return 0
    fi
    
    log_info "Removing $path_count file path(s) from history"
    
    # Build git-filter-repo command
    local filter_args=()
    while IFS= read -r path; do
        [[ -n "$path" ]] && filter_args+=("--path" "$path")
    done < "$paths_file"
    
    # Run git-filter-repo with --invert-paths to REMOVE the specified paths
    if git-filter-repo "${filter_args[@]}" --invert-paths --force 2>&1 | tee -a "$LOG_FILE"; then
        log_success "History rewritten successfully"
        rm -f "$paths_file"
        return 0
    else
        log_error "Failed to rewrite history"
        rm -f "$paths_file"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Force Push
#-------------------------------------------------------------------------------
force_push() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    log_subheader "Force Pushing: $repo_name"
    
    if [[ "$SKIP_PUSH" == true ]]; then
        log_warning "Force push skipped (--skip-push flag)"
        log_info "To push manually: cd $repo_dir && git push --force --all $GIT_REMOTE"
        return 0
    fi
    
    cd "$repo_dir"
    
    # Re-add remote if it was removed by git-filter-repo
    if ! git remote get-url "$GIT_REMOTE" &>/dev/null; then
        log_warning "Remote '$GIT_REMOTE' not found. It may have been removed by git-filter-repo."
        log_info "Please manually add the remote and push:"
        echo "  cd $repo_dir"
        echo "  git remote add $GIT_REMOTE <remote-url>"
        echo "  git push --force --all $GIT_REMOTE"
        echo "  git push --force --tags $GIT_REMOTE"
        return 1
    fi
    
    # Force push all branches
    if git push --force --all "$GIT_REMOTE" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Force pushed all branches"
    else
        log_error "Failed to force push branches"
        return 1
    fi
    
    # Force push tags
    if git push --force --tags "$GIT_REMOTE" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Force pushed all tags"
    else
        log_warning "Failed to force push tags (may not have any)"
    fi
    
    return 0
}

#-------------------------------------------------------------------------------
# Verification
#-------------------------------------------------------------------------------
verify_cleanup() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    log_subheader "Verifying Cleanup: $repo_name"
    
    cd "$repo_dir"
    
    # Check for remaining large blobs
    local remaining=$(git rev-list --objects --all 2>/dev/null | \
        git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize)' 2>/dev/null | \
        awk -v threshold="$SIZE_THRESHOLD_BYTES" '$1 == "blob" && $3 >= threshold' | wc -l)
    
    if [[ $remaining -eq 0 ]]; then
        log_success "✓ No files larger than ${SIZE_THRESHOLD_MB}MB remain in history"
        
        # Show new repository size
        local repo_size=$(du -sh .git | cut -f1)
        log_info "Repository .git size: $repo_size"
        
        # Run git gc
        log_info "Running garbage collection..."
        git gc --prune=now --aggressive 2>&1 | tail -1
        
        local new_size=$(du -sh .git | cut -f1)
        log_info "Repository .git size after gc: $new_size"
        
        return 0
    else
        log_error "✗ Found $remaining large blob(s) still in history!"
        log_info "Run the following to investigate:"
        echo "  cd $repo_dir"
        echo "  git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | awk '\$1 == \"blob\" && \$3 >= $SIZE_THRESHOLD_BYTES'"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Process Single Repository
#-------------------------------------------------------------------------------
process_repository() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    log_header "Processing Repository: $repo_name"
    
    # Set log file for this repo
    LOG_FILE="${LOG_DIR}/${repo_name}-${TIMESTAMP}.log"
    touch "$LOG_FILE"
    
    log_info "Log file: $LOG_FILE"
    
    # Check if repo has large files
    local has_large_files=false
    if tail -n +2 "$REPORT_FILE" | grep -q "^\"$repo_name\""; then
        has_large_files=true
    fi
    
    if [[ "$has_large_files" != true ]]; then
        log_info "No large files found in this repository"
        return 0
    fi
    
    # Step 1: Create backup
    if ! create_backup "$repo_dir"; then
        log_error "Backup failed - aborting for safety"
        return 1
    fi
    
    # Step 2: Upload to S3
    upload_large_files_to_s3 "$repo_dir"
    
    # Step 3: Capture remote URL before it gets removed
    cd "$repo_dir"
    local remote_url=$(git remote get-url "$GIT_REMOTE" 2>/dev/null || echo "")

    # Step 4: Rewrite history
    if ! rewrite_history "$repo_dir"; then
        log_error "History rewrite failed"
        log_info "Restore from backup: tar -xzf ${BACKUP_DIR}/${repo_name}-${TIMESTAMP}.tar.gz"
        return 1
    fi
    
    # Step 5: Restore remote if it was removed
    if [[ -n "$remote_url" ]]; then
        cd "$repo_dir"
        if ! git remote get-url "$GIT_REMOTE" &>/dev/null; then
            log_info "Restoring remote '$GIT_REMOTE' ($remote_url)"
            git remote add "$GIT_REMOTE" "$remote_url"
        fi
    fi

    # Step 6: Force push
    force_push "$repo_dir"
    
    # Step 7: Verify
    verify_cleanup "$repo_dir"
    
    log_success "Repository processed: $repo_name"
}

#-------------------------------------------------------------------------------
# Confirmation Prompt
#-------------------------------------------------------------------------------
confirm_execution() {
    echo ""
    echo -e "${RED}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}                    ⚠️  WARNING: DESTRUCTIVE OPERATION  ⚠️${NC}"
    echo -e "${RED}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "This will:"
    echo "  1. Upload large files to S3"
    echo "  2. PERMANENTLY rewrite Git history"
    echo "  3. Force-push to remote repositories"
    echo ""
    echo "Commit hashes WILL change. All team members must re-clone."
    echo ""
    echo -e "Backups will be saved to: ${CYAN}$BACKUP_DIR${NC}"
    echo ""
    read -p "Type 'YES' (all caps) to proceed: " confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log_info "Aborted by user"
        exit 0
    fi
}

#-------------------------------------------------------------------------------
# Main Function
#-------------------------------------------------------------------------------
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --execute)
                EXECUTE_MODE=true
                shift
                ;;
            --size)
                SIZE_THRESHOLD_MB="$2"
                SIZE_THRESHOLD_BYTES=$((SIZE_THRESHOLD_MB * 1024 * 1024))
                shift 2
                ;;
            --bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            --remote)
                GIT_REMOTE="$2"
                shift 2
                ;;
            --skip-s3)
                SKIP_S3=true
                shift
                ;;
            --skip-push)
                SKIP_PUSH=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "Git Large File Cleaner v${VERSION}"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                if [[ -z "$PARENT_DIR" ]]; then
                    PARENT_DIR="$1"
                else
                    log_error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate parent directory
    if [[ -z "$PARENT_DIR" ]]; then
        log_error "Parent directory is required"
        echo "Use --help for usage information"
        exit 1
    fi
    
    if [[ ! -d "$PARENT_DIR" ]]; then
        log_error "Directory does not exist: $PARENT_DIR"
        exit 1
    fi
    
    PARENT_DIR=$(realpath "$PARENT_DIR")
    
    # Setup output directories
    OUTPUT_DIR="${PARENT_DIR}/git-cleaner-output-${TIMESTAMP}"
    BACKUP_DIR="${OUTPUT_DIR}/backups"
    LOG_DIR="${OUTPUT_DIR}/logs"
    REPORT_FILE="${OUTPUT_DIR}/large-files-report.csv"
    
    mkdir -p "$OUTPUT_DIR" "$BACKUP_DIR" "$LOG_DIR"
    
    # Display banner
    log_header "Git Large File Cleaner v${VERSION}"
    
    echo -e "Configuration:"
    echo -e "  Parent Directory:  ${CYAN}$PARENT_DIR${NC}"
    echo -e "  Size Threshold:    ${CYAN}${SIZE_THRESHOLD_MB} MB${NC}"
    echo -e "  S3 Bucket:         ${CYAN}$S3_BUCKET${NC}"
    echo -e "  Git Remote:        ${CYAN}$GIT_REMOTE${NC}"
    echo -e "  Mode:              ${CYAN}$(if $EXECUTE_MODE; then echo 'EXECUTE'; else echo 'DRY-RUN'; fi)${NC}"
    echo -e "  Output Directory:  ${CYAN}$OUTPUT_DIR${NC}"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Find repositories
    mapfile -t REPOS < <(find_git_repos "$PARENT_DIR")
    
    if [[ ${#REPOS[@]} -eq 0 ]]; then
        log_error "No Git repositories found"
        exit 1
    fi
    
    # Generate report for all repos
    log_header "Scanning All Repositories"
    local total_files=$(generate_csv_report "${REPOS[@]}")
    
    if [[ "$total_files" -eq 0 ]]; then
        log_success "No files larger than ${SIZE_THRESHOLD_MB}MB found in any repository"
        log_info "Nothing to clean!"
        exit 0
    fi
    
    # Dry-run: show preview and exit
    if [[ "$EXECUTE_MODE" != true ]]; then
        display_preview
        exit 0
    fi
    
    # Execution mode: confirm and process
    confirm_execution
    
    log_header "Executing Cleanup"
    
    local success_count=0
    local fail_count=0
    
    for repo_dir in "${REPOS[@]}"; do
        if process_repository "$repo_dir"; then
            ((success_count++)) || true
        else
            ((fail_count++)) || true
        fi
    done
    
    # Final summary
    log_header "Execution Complete"
    
    echo -e "Results:"
    echo -e "  Repositories processed: ${CYAN}${#REPOS[@]}${NC}"
    echo -e "  Successful:             ${GREEN}$success_count${NC}"
    echo -e "  Failed:                 ${RED}$fail_count${NC}"
    echo ""
    echo -e "Output files:"
    echo -e "  Report:  ${CYAN}$REPORT_FILE${NC}"
    echo -e "  Backups: ${CYAN}$BACKUP_DIR${NC}"
    echo -e "  Logs:    ${CYAN}$LOG_DIR${NC}"
    echo ""
    
    if [[ $fail_count -gt 0 ]]; then
        log_warning "Some repositories failed. Check logs for details."
        exit 1
    fi
    
    log_success "All repositories cleaned successfully!"
    
    echo ""
    echo -e "${BOLD}Manual Verification Commands:${NC}"
    echo ""
    echo "# List any remaining large blobs in a repo:"
    echo "cd <repo-dir>"
    echo "git rev-list --objects --all | \\"
    echo "  git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize)' | \\"
    echo "  awk '\$1 == \"blob\" && \$3 >= $SIZE_THRESHOLD_BYTES'"
    echo ""
    echo "# Verify S3 uploads:"
    echo "aws s3 ls s3://${S3_BUCKET}/ --recursive"
    echo ""
    echo "# Check repository integrity:"
    echo "git fsck --full"
}

#-------------------------------------------------------------------------------
# Entry Point
#-------------------------------------------------------------------------------
main "$@"

