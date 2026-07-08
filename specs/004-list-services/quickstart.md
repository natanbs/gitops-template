# Quickstart: List Available Services

## List all services

```bash
decommission --list
```

## List services in a specific namespace

```bash
decommission --list --namespace production
```

## List services as JSON

```bash
decommission --list --json
```

## Example output

```text
NAMESPACE     NAME            MODEL     STATUS     REPLICAS
default       my-api          direct    Ready      3/3
production    web-frontend    gitops    Ready      5/5
staging       cache-redis     direct    Not Ready  0/1
```
