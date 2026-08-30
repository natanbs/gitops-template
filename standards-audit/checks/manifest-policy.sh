#!/usr/bin/env bash
# standards-audit/checks/manifest-policy.sh — policy-manifests check (app-k8s).
# * value-level agreement only (port, namespace, image tag, PVC, cronjob);
#   non-overlapping with structure (structure owns FORMAT parse).
# * .env authoritative when present; manifests must agree with it.
# * .env absent (CI checkout) -> cross-manifest internal consistency.
# * port agreement is scoped to the app's serving surface (deploy/svc/ingress —
#   the manifests build.sh renders from .env). Auxiliary workloads
#   (e.g. a MinIO sidecar on 9000/9001) and policy rules (NetworkPolicy DNS)
#   are their own concern and are never compared to CONTAINER_PORT.
# * aux subsystems (<key>-deploy/-svc/-ingress.yaml) are still validated for
#   internal port coherence: svc targetPort must be exposed by its deployment,
#   ingress backends must be served by its service.
# * raw source templates (*.tmpl.yaml) are excluded from the manifest surface —
#   placeholders like ${K8S_NAMESPACE} are not values.
# * non-app-k8s profiles or absent k8s/ -> N/A, never FAIL.
set -euo pipefail

check_id="policy-manifests"
repo_root="${1:?repo-root required}"
profile="${2:?profile required}"

case "$profile" in
  app-k8s) ;;
  *)
    printf '[N/A]\t%s\tno k8s/ manifests for profile '\''%s'\''\n' "$check_id" "$profile"
    exit 0
    ;;
esac

# --- applicable inputs: k8s manifests (rendered files, not templates) ---------
manifests=""
for f in "$repo_root"/k8s/*.yaml; do
  [[ -e "$f" ]] || continue
  case "$(basename "$f")" in
    *.tmpl.yaml) continue ;;
  esac
  manifests="${manifests}${manifests:+$'\n'}$(basename "$f")"
done
if [[ -z "$manifests" ]]; then
  printf '[N/A]\t%s\tno k8s/ manifests for profile '\''%s'\''\n' "$check_id" "$profile"
  exit 0
fi

# App serving surface: the manifests whose network ports must equal
# CONTAINER_PORT. Auxiliary workloads (minio-*, redis-*, sidecars) and policy
# objects (NetworkPolicy) run on their own ports and are excluded.
app_surface="deploy.yaml"$'\n'"svc.yaml"$'\n'"ingress.yaml"

# --- helpers (grep/awk only, BSD+GNU portable) --------------------------------
yaml_scalar() { # <file> <key-regex> -> first key value (quotes stripped, inner spaces kept)
  awk -v re="$2" '
    $0 ~ re {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      gsub(/^"|"$/, "", v)
      print v
      exit
    }' "$1"
}

ports_in() { # <file> -> distinct container-app port-ish values, one per line
  # Only resources that own application container ports are scanned. Network
  # policy rules (NetworkPolicy, egress/ingress DNS) carry non-app ports like 53
  # and must never be compared against CONTAINER_PORT.
  awk '
    /^[[:space:]]*kind:[[:space:]]*[^[:space:]]+/ {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]+#.*$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      kind = v
      next
    }
    /^---/ { kind = ""; next }
    /^[[:space:]]*-?[[:space:]]*(containerPort|targetPort|port|number):[[:space:]]*[0-9]+/ {
      if (kind != "Deployment" && kind != "StatefulSet" && kind != "DaemonSet" && \
          kind != "ReplicaSet" && kind != "Pod" && kind != "Service" && \
          kind != "Ingress" && kind != "CronJob") next
      v = $0
      sub(/^[^0-9]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      print v
    }' "$1" | sort -n | uniq
}

env_value() { # <file> <KEY> -> value from a name=value .env
  awk -F= -v k="$2" '$1 == k { print $2; exit }' "$1"
}

fail_violation() { # <detail> <fix>
  printf '[FAIL]\t%s\t%s\tfix: %s\n' "$check_id" "$1" "$2"
  exit 1
}

container_ports_in() { # <file> -> distinct numeric containerPort values declared by a workload
  awk '
    /^[[:space:]]*-?[[:space:]]*containerPort:[[:space:]]*[0-9]+/ {
      v = $0
      sub(/^[^0-9]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      print v
    }' "$1" | sort -n | uniq
}

service_target_ports() { # <file> -> numeric targetPort values, or port when empty
  awk '
    /^[[:space:]]*-?[[:space:]]*targetPort:[[:space:]]*[0-9]+/ {
      v = $0
      sub(/^[^0-9]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      tp = tp "\n" v
      has_tp = 1
      next
    }
    /^[[:space:]]*-?[[:space:]]*port:[[:space:]]*[0-9]+/ {
      v = $0
      sub(/^[^0-9]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      p = p "\n" v
      next
    }
    END { print (has_tp ? tp : p) }' "$1" | grep -E '^[0-9]+$'
}

ingress_backend_ports() { # <file> -> distinct numeric backend service.port.number values
  awk '
    /^[[:space:]]*-?[[:space:]]*number:[[:space:]]*[0-9]+/ {
      v = $0
      sub(/^[^0-9]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      print v
    }' "$1" | sort -n | uniq
}

# --- value-level extraction ---------------------------------------------------
env_file=""
if [[ -f "$repo_root/.env" ]]; then
  env_file="$repo_root/.env"
fi

deploy="$repo_root/k8s/deploy.yaml"
cronjob="$repo_root/k8s/cronjob.yaml"

if [[ -n "$env_file" ]]; then
  # -------- authoritative mode: manifests must agree with .env -------------
  expected_port="$(env_value "$env_file" CONTAINER_PORT)"
  if [[ -n "$expected_port" ]]; then
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      file="$repo_root/k8s/$m"
      [[ -f "$file" ]] || continue
      while IFS= read -r v; do
        [[ -n "$v" ]] || continue
        if [[ "$v" != "$expected_port" ]]; then
          fail_violation "k8s/$m port $v disagrees with CONTAINER_PORT=$expected_port (from .env)" "align k8s/$m ports to CONTAINER_PORT=$expected_port (or regenerate with build.sh)"
        fi
      done < <(ports_in "$file")
    done <<<"$app_surface"
  fi

  expected_ns="$(env_value "$env_file" K8S_NAMESPACE)"
  if [[ -n "$expected_ns" ]]; then
    for m in deploy svc ingress; do
      file="$repo_root/k8s/$m.yaml"
      [[ -f "$file" ]] || continue
      ns="$(yaml_scalar "$file" '^[[:space:]]*namespace:[[:space:]]*[^[:space:]]+')"
      if [[ -n "$ns" && "$ns" != "$expected_ns" ]]; then
        fail_violation "k8s/$m.yaml namespace '$ns' disagrees with K8S_NAMESPACE=$expected_ns (from .env)" "align k8s/$m.yaml metadata.namespace to K8S_NAMESPACE=$expected_ns"
      fi
    done
  fi

  expected_tag="$(env_value "$env_file" IMAGE_TAG)"
  if [[ -n "$expected_tag" && -f "$deploy" ]]; then
    image="$(yaml_scalar "$deploy" '^[[:space:]]*image:[[:space:]]*[^[:space:]]+')"
    if [[ -n "$image" ]]; then
      tag="${image##*:}"
      if [[ "$tag" != "$expected_tag" ]]; then
        fail_violation "k8s/deploy.yaml image '$image' tag '$tag' disagrees with IMAGE_TAG=$expected_tag (from .env)" "set k8s/deploy.yaml image tag to IMAGE_TAG=$expected_tag"
      fi
    fi
  fi

  expected_pvc="$(env_value "$env_file" PVC_NAME)"
  if [[ -n "$expected_pvc" ]]; then
    claim="$(yaml_scalar "$deploy" '^[[:space:]]*claimName:[[:space:]]*[^[:space:]]+')"
    if [[ -n "$claim" && "$claim" != "$expected_pvc" ]]; then
      fail_violation "k8s/deploy.yaml claimName '$claim' disagrees with PVC_NAME=$expected_pvc (from .env)" "align k8s/deploy.yaml volume claim to PVC_NAME=$expected_pvc"
    fi
  fi

  expected_cron="$(env_value "$env_file" CRON_SCHEDULE)"
  if [[ -n "$expected_cron" && -f "$cronjob" ]]; then
    sched="$(yaml_scalar "$cronjob" '^[[:space:]]*schedule:[[:space:]]*[^[:space:]]+')"
    if [[ -n "$sched" && "$sched" != "$expected_cron" ]]; then
      fail_violation "k8s/cronjob.yaml schedule '$sched' disagrees with CRON_SCHEDULE=$expected_cron (from .env)" "align k8s/cronjob.yaml schedule to CRON_SCHEDULE=$expected_cron"
    fi
  fi
else
  # -------- fallback: cross-manifest internal consistency -------------------
  port_set=""
  ns_set=""
  image_set=""
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    file="$repo_root/k8s/$m"
    [[ -f "$file" ]] || continue
    while IFS= read -r v; do
      [[ -n "$v" ]] || continue
      port_set="${port_set}${port_set:+$'\n'}${v}"
    done < <(ports_in "$file")
  done <<<"$app_surface"
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    file="$repo_root/k8s/$m"
    [[ -f "$file" ]] || continue
    ns="$(yaml_scalar "$file" '^[[:space:]]*namespace:[[:space:]]*[^[:space:]]+')"
    if [[ -n "$ns" ]]; then
      ns_set="${ns_set}${ns_set:+$'\n'}${ns}"
    fi
    image="$(yaml_scalar "$file" '^[[:space:]]*image:[[:space:]]*[^[:space:]]+')"
    if [[ -n "$image" ]]; then
      image_set="${image_set}${image_set:+$'\n'}${image}"
    fi
  done <<<"$manifests"

  distinct_ports="$(printf '%s\n' "$port_set" | sort -n | uniq)"
  distinct_ns="$(printf '%s\n' "$ns_set" | sort -u)"
  distinct_images="$(printf '%s\n' "$image_set" | sort -u)"

  if [[ "$(printf '%s\n' "$distinct_ports" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" -gt 1 ]]; then
    values="$(printf '%s\n' "$distinct_ports" | grep -v '^[[:space:]]*$' | tr '\n' ' ')"
    fail_violation "k8s/ manifests disagree on ports ($values)" "set containerPort/targetPort/port to one value across deploy/svc/ingress (or generate with build.sh)"
  fi
  if [[ "$(printf '%s\n' "$distinct_ns" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" -gt 1 ]]; then
    values="$(printf '%s\n' "$distinct_ns" | grep -v '^[[:space:]]*$' | tr '\n' ' ')"
    fail_violation "k8s/ manifests disagree on namespace ($values)" "set metadata.namespace to one value across manifests"
  fi
  if [[ "$(printf '%s\n' "$distinct_images" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" -gt 1 ]]; then
    values="$(printf '%s\n' "$distinct_images" | grep -v '^[[:space:]]*$' | tr '\n' ' ')"
    fail_violation "k8s/ manifests disagree on image reference ($values)" "use one image reference across manifests"
  fi
fi

# --- aux-workload subsystem coherence ---------------------------------------
# Sidecar/aux subsystems (<key>-deploy/-svc/-ingress.yaml, e.g. minio-*) are
# exempt from the CONTAINER_PORT binding (they serve their own ports) but must
# still be internally coherent: every service targetPort must be exposed by the
# matching deployment, and every ingress backend number must be served by the
# matching service. Runs in both authoritative and fallback modes.
while IFS= read -r m; do
  [[ "$m" == *-deploy.yaml ]] || continue
  key="${m%-deploy.yaml}"
  deploy_file="$repo_root/k8s/$key-deploy.yaml"
  svc_file="$repo_root/k8s/$key-svc.yaml"
  ingress_file="$repo_root/k8s/$key-ingress.yaml"
  [[ -f "$deploy_file" ]] || continue

  container_ports="$(container_ports_in "$deploy_file")"
  if [[ -f "$svc_file" ]]; then
    while IFS= read -r t; do
      [[ -n "$t" ]] || continue
      if ! grep -Fxq "$t" <<<"$container_ports"; then
        exposed="$(printf '%s' "$container_ports" | tr '\n' ' ')"
        fail_violation "k8s/$key-svc.yaml targetPort $t is not exposed by k8s/$key-deploy.yaml (containerPorts: $exposed)" "set $key-svc.yaml targetPort to one of the containerPorts exposed by $key-deploy.yaml"
      fi
    done < <(service_target_ports "$svc_file")
  fi
  if [[ -f "$svc_file" && -f "$ingress_file" ]]; then
    svc_ports="$(service_target_ports "$svc_file")"
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      if ! grep -Fxq "$n" <<<"$svc_ports"; then
        served="$(printf '%s' "$svc_ports" | tr '\n' ' ')"
        fail_violation "k8s/$key-ingress.yaml backend number $n is not served by k8s/$key-svc.yaml (published via $key-svc.yaml: $served)" "set $key-ingress.yaml backend number to a port served by $key-svc.yaml"
      fi
    done < <(ingress_backend_ports "$ingress_file")
  fi
done <<<"$manifests"

printf '[PASS]\t%s\tk8s/ manifests agree with declared config (or are internally consistent)\n' "$check_id"
exit 0