# Quickstart: YAML Tag Update

## Prerequisites

- Existing tag.sh script (from previous feature)
- Kubernetes manifest files in `k8s/` subdirectory
- Docker image built and available locally

## Usage

Navigate to the app folder with `k8s/` subdirectory, then run:

```bash
cd services/myapp/
../../gitops-template/tag.sh v2.0.0
```

The script will:
1. Update `CURRENT_TAG=v2.0.0` in the repository root's `.env`
2. Update image tags in `k8s/deploy.yaml` (if exists)
3. Update image tags in `k8s/cronjob.yaml` (if exists)
4. Push `myapp:v2.0.0` to `localhost:50000`
5. Create and push git tag `v2.0.0`

## Examples

### Release with deploy.yaml

```bash
cd services/api-gateway/
../../gitops-template/tag.sh v1.5.0

# Output:
# Processing release for image: api-gateway
# Target release version: v1.5.0
# [1/4] Verifying local image api-gateway:latest exists...
# [2/4] Updating CURRENT_TAG in .env...
# Updated CURRENT_TAG=v1.5.0 in .env
# [2/5] Updating image tags in k8s/deploy.yaml...
# Updated image tags in k8s/deploy.yaml
# [3/5] Tagging Docker image from [api-gateway:latest] to [localhost:50000/api-gateway:v1.5.0]...
# Pushing Docker image to registry...
# [4/5] Creating Git tag v1.5.0 on main branch...
# Successfully bumped both Git and Docker to v1.5.0!
```

### Release with both YAML files

```bash
cd services/web-app/
../../gitops-template/tag.sh v2.0.0

# Output includes both deploy.yaml and cronjob.yaml updates
```

### Release without YAML files

```bash
cd services/simple-app/
../../gitops-template/tag.sh v1.0.0

# Output:
# Processing release for image: simple-app
# Target release version: v1.0.0
# [1/4] Verifying local image simple-app:latest exists...
# [2/4] Updating CURRENT_TAG in .env...
# Updated CURRENT_TAG=v1.0.0 in .env
# [2/5] Skipping YAML updates - no k8s/ directory found
# [3/5] Tagging Docker image...
# ...
```

## Verification

After running the script, verify:

```bash
# Check .env
grep CURRENT_TAG ../../.env

# Check deploy.yaml
grep "image:" k8s/deploy.yaml

# Check cronjob.yaml
grep "image:" k8s/cronjob.yaml

# Check Docker image in registry
curl http://localhost:50000/v2/<image_name>/tags/list

# Check git tag
git tag -l v2.0.0
```

## Troubleshooting

### "No image: lines found in k8s/deploy.yaml"

The YAML file exists but doesn't contain any image references. Check the file format.

### "k8s/ directory not found"

The script skips YAML updates when the `k8s/` directory doesn't exist. This is expected behavior.

### "sed: invalid option"

This shouldn't happen - the script uses portable sed syntax. If it does, check your shell environment.

## Configuration

### YAML File Paths

The script looks for YAML files in `k8s/` subdirectory. To change:

1. Edit `tag.sh`
2. Modify the YAML file paths in the update function

### Image Tag Pattern

The script matches lines containing `image:`. To change the pattern:

1. Edit `tag.sh`
2. Modify the sed pattern in the update function

## Testing

### Manual Test

```bash
# 1. Create test YAML files
mkdir -p k8s/
cat > k8s/deploy.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
      - name: myapp
        image: localhost:50000/myapp:v1.0.0
EOF

# 2. Run the script
../../gitops-template/tag.sh v2.0.0

# 3. Verify YAML was updated
grep "image:" k8s/deploy.yaml
# Should show: image: localhost:50000/myapp:v2.0.0
```

### Lint Check

```bash
shellcheck tag.sh
```
