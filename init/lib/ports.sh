# Shared port-sync helpers for existing-app manifests (BSD/GNU sed compatible).
# Rewrites only the intended port fields in place; leaves all other content alone.

sync_svc_ports() {  # <file> <port>
  sed -i.bak \
    -e "s/^\([[:space:]]*port:\)[[:space:]]*[0-9]*/\1 ${2}/" \
    -e "s/^\([[:space:]]*-[[:space:]]*port:\)[[:space:]]*[0-9]*/\1 ${2}/" \
    -e "s/^\([[:space:]]*targetPort:\)[[:space:]]*[0-9]*/\1 ${2}/" \
    "$1" && rm -f "$1.bak"
}

sync_ingress_number() {  # <file> <port>
  sed -i.bak \
    -e "s/^\([[:space:]]*number:\)[[:space:]]*[0-9]*/\1 ${2}/" \
    "$1" && rm -f "$1.bak"
}
