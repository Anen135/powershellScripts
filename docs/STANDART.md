**Rule**
1. `Write-Output` - Used for data

2. `Write-Host` - Used for:
    - Colored
    - Progress output
    - TUI interfaces
    - Decorative messages

3. `Write-Warning` - Used for warnings

4. `Write-Error` - Used for errors

**Standart**: 
1. Each release is accompanied by an update: docs/CHANGELOG.md
2. All new scripts must support: -Verbose

4. Add validation attributes where appropriate:
    - `[ValidateNotNullOrEmpty()]` for mandatory strings
    - `[ValidateScript()]` for path validation
    - `[ValidateSet()]` where applicable

5. Each script starts with a comment-based help
6. For version updates, format: "X.Y - Changelog"

**Author**: Anen

**Gitflow**
- For new feature: Write TODO.md file.
- For new release: Update CHANGELOG.md file.