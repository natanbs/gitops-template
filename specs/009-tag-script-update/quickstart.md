# Quickstart: Tag Script Update

## Prerequisites

- Docker installed and running
- Git repository cloned with remote named `origin`
- Local Docker image built and tagged as `<image_name>:latest`
- `.env` file in repository root with `CURRENT_TAG` entry (optional - script handles missing file)

## Usage

Navigate to the app folder you want to release, then run:

```bash
cd services/myapp/
../../gitops-template/tag.sh v2.0.0
```

The script will:
1. Update `CURRENT_TAG=v2.0.0` in the repository root's `.env`
2. Push `myapp:v2.0.0` to `localhost:50000`
3. Create and push git tag `v2.0.0`

## Examples

### Release a service

```bash
cd services/api-gateway/
../../gitops-template/tag.sh v1.5.0

# Output:
# Processing release for image: api-gateway
# Target release version: v1.5.0
# Updating .env CURRENT_TAG to v1.5.0...
# Tagging Docker image from [api-gateway:latest] to [localhost:50000/api-gateway:v1.5.0]...
# Pushing Docker image to registry...
# Creating Git tag v1.5.0 on main branch...
# Successfully bumped both Git and Docker to v1.5.0!
```

### Release from nested folder

```bash
cd apps/web/frontend/
../../../../gitops-template/tag.sh v2.0.0
```

## Verification

After running the script, verify:

```bash
# Check .env
grep CURRENT_TAG ../../.env

# Check Docker image in registry
curl http://localhost:50000/v2/<image_name>/tags/list

# Check git tag
git tag -l v2.0.0
```

## Troubleshooting

### "Local image not found"

Build your image first:
```bash
cd services/myapp/
docker build -t myapp:latest .
```

### "Permission denied"

Make the script executable:
```bash
chmod +x ../../gitops-template/tag.sh
```

### "sed: invalid option"

This shouldn't happen - the script uses portable sed syntax. If it does, check your shell environment.

## Configuration

### Registry Settings

The registry is hardcoded to `localhost:50000`. To change:

1. Edit `tag.sh`
2. Modify these lines:
   ```bash
   REGISTRY_CLUSTER_URL="localhost"
   REGISTRY_CLUSTER_PORT="50000"
   ```

### Image Name Derivation

Image name is derived from current folder name using `basename "$PWD"`. To override, you would need to modify the script to accept an optional first argument.

## Testing

### Manual Test

```bash
# 1. Build a test image
cd services/myapp/
docker build -t myapp:latest .

# 2. Run the script
../../gitops-template/tag.sh v1.0.0-test

# 3. Verify all three side effects
grep CURRENT_TAG ../../.env
curl http://localhost:50000/v2/myapp/tags/list
git tag -l v1.0.0-test
```

### Lint Check

```bash
shellcheck tag.sh
```
