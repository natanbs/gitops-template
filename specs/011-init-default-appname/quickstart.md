# Quickstart: init.sh Default App Name from Folder

## What Changed

`init.sh --app-name` is now **optional**. When omitted, the script uses your current directory name as the app name.

## Before

```bash
# Required: always pass --app-name
./init.sh --app-name my-api
```

## After

```bash
# Option 1: Navigate to target directory, run without --app-name
cd my-api
../gitops-template/init.sh

# Option 2: Still works exactly as before
./init.sh --app-name my-api
```

## Validation

The script validates the derived name against Kubernetes naming rules:
- Lowercase letters, numbers, and hyphens only
- Must start and end with a letter or number
- Max 253 characters

If the folder name fails validation, the script aborts with a clear error and tells you to either rename the folder or provide `--app-name` explicitly.

## Blocklist

Known repository-level names (e.g., `gitops-template`) are rejected when derived from the folder name. Provide `--app-name` to override.

## Testing

```bash
# Test default from folder
mkdir /tmp/test-app && cd /tmp/test-app
/path/to/gitops-template/init.sh
# Should scaffold in /tmp/test-app with APP_NAME=test-app

# Test explicit override
cd /tmp
/path/to/gitops-template/init.sh --app-name my-api
# Should create /tmp/my-api/ (existing behavior)

# Test invalid name
mkdir /tmp/My_App.Name && cd /tmp/My_App.Name
/path/to/gitops-template/init.sh
# Should abort with K8s validation error

# Test blocklist
mkdir /tmp/gitops-template && cd /tmp/gitops-template
/path/to/gitops-template/init.sh
# Should abort with blocklist error
```
