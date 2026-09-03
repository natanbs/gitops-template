#!/usr/bin/env sh
# Bootstrap script that logs into Vault with a static token (anti-pattern).
# NOTE: A committed VAULT_TOKEN is a static, long-lived credential — VS-007 FAIL.
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="s.t9UfYySPZxjSZ8dC4iCp6GTN"
