# POC: Disable Git LFS After Bitbucket → GitHub Migration

## 1. Objective

To validate:

-   Whether Git LFS can be disabled **after migration to GitHub**
-   Impact on:
    -   existing LFS files\
    -   commit history\
    -   future commits\
    -   developer workflow

------------------------------------------------------------------------

## 2. Test Environment

-   OS: Ubuntu 22.04\
-   Source: Bitbucket repository with Git LFS enabled\
-   Target: GitHub repository\
-   Test file size:
    -   Large file: **126MB (.bin)**\
    -   New test file: **5MB (.bin)**

------------------------------------------------------------------------

## 3. Steps Performed

### 3.1 Bitbucket Repository Setup (With LFS)

1.  Initialized repository and enabled LFS:

```{=html}
<!-- -->
```
    git init
    git lfs install
    git lfs track "*.bin"
    git add .gitattributes
    git commit -m "enable git lfs"

2.  Added large file (126MB):

```{=html}
<!-- -->
```
    dd if=/dev/zero of=old_large.bin bs=1M count=120
    git add old_large.bin
    git commit -m "add large file in bitbucket"

3.  Added normal code file:

```{=html}
<!-- -->
```
    echo "print('hello from bitbucket')" > app.py
    git add app.py
    git commit -m "normal code file"

4.  Pushed to Bitbucket:

```{=html}
<!-- -->
```
    git push -u origin master

**Result:**\
Large file stored via **Git LFS on Bitbucket**.

<img width="915" height="365" alt="image" src="https://github.com/user-attachments/assets/89dde40d-0b58-4274-ad48-aa9d2eafa3f7" />

<img width="1115" height="551" alt="image" src="https://github.com/user-attachments/assets/1feac657-6aed-418e-8185-b152731c8d57" />

<img width="1256" height="302" alt="image" src="https://github.com/user-attachments/assets/9f2fe2a5-7479-4067-96cb-f8892ecfe58f" />



------------------------------------------------------------------------

### 3.2 Migration to GitHub

1.  Added GitHub as remote\
2.  Pushed Git objects\
3.  Pushed LFS objects separately:

```{=html}
<!-- -->
```
    git lfs push --all github

**Result:**\
Repository successfully migrated with:

-   commit history intact\
-   LFS pointers preserved\
-   large file downloadable from GitHub LFS

<img width="1375" height="107" alt="image" src="https://github.com/user-attachments/assets/3103308f-33e6-4c29-a1dd-ca10c64f5b76" />


------------------------------------------------------------------------

### 3.3 Post-Migration Validation

Verified current LFS state on GitHub clone:

    git lfs ls-files

**Output:**

    5c4fb902a2 * old_large.bin

**Confirmation:** Existing large file still managed by LFS.

------------------------------------------------------------------------

<img width="701" height="164" alt="Screenshot from 2026-02-05 23-25-16" src="https://github.com/user-attachments/assets/d77b8822-a18f-4c4c-9344-b432984011cd" />


### 3.4 Disable LFS After Migration

1.  Remove LFS rules:

```{=html}
<!-- -->
```
    nano .gitattributes   # removed *.bin lfs rule
    git add .gitattributes
    git commit -m "fix: remove all lfs tracking rules"
    git push

2.  Created new file after LFS removal:

```{=html}
<!-- -->
```
    dd if=/dev/zero of=final_test.bin bs=1M count=5
    git add final_test.bin
    git commit -m "final test without lfs"
    git push

3.  Verified again:

```{=html}
<!-- -->
```
    git lfs ls-files

**Output:**

    5c4fb902a2 * old_large.bin

**Result:**\
New file NOT listed in LFS -- stored as normal Git object.

------------------------------------------------------------------------

## 4. POC Result

### Observations

  Area                 Result
  -------------------- ----------------------
  Existing LFS files   Continue to work
  Commit history       Unchanged
  New commits          Stored as normal Git
  Re-clone required    No
  History rewrite      Not required
  Developer impact     Minimal

------------------------------------------------------------------------

### Conclusion

Git LFS **can be disabled post migration** with following behavior:

1.  **Existing large files remain in LFS**\
2.  **Future files bypass LFS and use normal Git storage**\
3.  No impact to:
    -   commit SHAs\
    -   branches\
    -   history\
    -   existing clones

------------------------------------------------------------------------

## 5. Risks & Limitations

1.  After disabling LFS:
    -   Any new file \>100MB will be **rejected by GitHub**
2.  Existing LFS storage will still incur cost
3.  Teams must be informed to avoid committing large binaries

------------------------------------------------------------------------

## 6. Recommended Approach

1.  Disable LFS after migration\
2.  Use external artifact storage for future large files\
3.  Keep legacy LFS only for historical objects

------------------------------------------------------------------------

## Final Statement

The POC confirms that Git LFS can be safely disabled after GitHub
migration without rewriting history or impacting existing repositories.
Future commits will behave as standard Git while legacy LFS files remain
accessible.
