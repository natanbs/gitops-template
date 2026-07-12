# Data Model: Fix ArgoCD Gitignore Conflict

Not applicable. This feature modifies a gitignore template file — no data entities, relationships, or state transitions are involved.

The "data" in this context is the set of gitignore rules in `init/gitignore`, which is a flat list of patterns. The change removes two patterns (`k8s/*.yaml` and `argocd/*.yaml`) from this list.
