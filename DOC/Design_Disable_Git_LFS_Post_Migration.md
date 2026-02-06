# Design Document -- Disabling Git LFS After GitHub Migration

## 1. Problem Statement

**Current State**

-   Repositories have been migrated from **Bitbucket → GitHub**
-   Historical large files are stored using **Git LFS**
-   Business requirement:

> "Can we disable Git LFS in GitHub after migration without impacting
> existing data, history, branches, and developer workflow?"

### Key Expectations

-   Commit history must remain intact
-   Branches and PRs must not be affected
-   Teams should continue working on GitHub without disruption
-   Only future commit behavior may change

------------------------------------------------------------------------

## 2. Direct Answer

**Yes -- Git LFS can be disabled post migration**

This can be done **without:**

-   rewriting history
-   modifying commit SHAs
-   impacting branches or tags
-   breaking existing clones

------------------------------------------------------------------------

## 3. Approach (Recommended Method)

### Step 1 -- Post Migration Validation

Before disabling LFS, validate:

-   All historical large files are downloadable
-   Build pipelines function correctly
-   Applications can access required assets

------------------------------------------------------------------------

### Step 2 -- Disable LFS for Future Commits

**Actions Required**

1.  Remove LFS tracking rules from repository
    -   Update `.gitattributes`
2.  Commit and push the change
3.  Do NOT perform history rewrite
4.  Keep existing LFS objects untouched

**Resulting Behavior**

-   Old large files → remain in LFS
-   New files → stored as normal Git objects

------------------------------------------------------------------------

### Step 3 -- Governance Setup

After disabling LFS:

-   Introduce file-size checks in CI
-   Define alternate storage for binaries
-   Communicate changes to development teams

------------------------------------------------------------------------

## 4. Expected Outcome

### 4.1 What Will NOT Change

  Area              Impact
  ----------------- ---------------------
  Commit History    No change
  Commit Hashes     Unchanged
  Branches          Unaffected
  Pull Requests     Continue to work
  Existing Clones   No reclone required
  Tags              Intact
  Pipelines         No impact

------------------------------------------------------------------------

### 4.2 What WILL Change

  Area              Behavior
  ----------------- -----------------------------
  New large files   Will NOT use LFS
  GitHub limit      100MB file limit will apply
  Storage           Only legacy LFS remains

------------------------------------------------------------------------

## 5. Risks

### 5.1 Technical Risks

1.  **GitHub Native Limit**

-   After LFS disable:
    -   Any file \>100MB → push will be rejected
    -   Even same extensions as legacy files will be blocked

2.  **Mixed Storage Model**

-   Historical → LFS
-   Future → Normal Git
-   Possible confusion in tooling

3.  **Storage Cost**

-   Existing LFS objects will continue to incur cost

------------------------------------------------------------------------

### 5.2 Operational Risks

-   Developers may commit large binaries unknowingly
-   Build tools expecting LFS may need modification
-   Onboarding documentation update required

------------------------------------------------------------------------

## 6. Mitigation Plan

1.  **Introduce Controls**

-   Pre-commit hooks
-   CI file-size validation
-   GitHub ruleset

2.  **Alternative Storage**

-   Artifact repository
-   Object storage (S3 / Artifactory)
-   Package registry

3.  **Communication**

-   Team guideline
-   Migration note
-   SOP for binaries

------------------------------------------------------------------------

## 7. Rollback Strategy

If disabling LFS causes issues:

-   Re-enable LFS tracking
-   No history change required
-   Existing objects remain valid

------------------------------------------------------------------------

## 8. Recommendation

### Preferred Model

1.  Disable Git LFS after migration
2.  Keep LFS only for historical data
3.  Use external storage for new binaries
4.  Enforce size governance

**Benefits**

-   Zero history impact
-   Clean future workflow
-   Cost control
-   Simplified Git operations

------------------------------------------------------------------------

## 9. Final Conclusion

-   Git LFS can be safely disabled after GitHub migration
-   No impact to history, branches, or existing work
-   Only future commits behavior changes
-   Governance required for large files
-   Legacy LFS cost will remain

------------------------------------------------------------------------

### Business Decision

> Recommended to disable Git LFS on GitHub post migration and manage
> future large files through dedicated artifact storage instead of Git.
