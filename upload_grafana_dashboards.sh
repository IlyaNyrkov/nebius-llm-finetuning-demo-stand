#!/bin/bash

GRAFANA_URL="https://$2"
USER="admin"
PASSWORD="$1"
DASHBOARDS_DIR="./grafana_dashboards"

for dashboard in "$DASHBOARDS_DIR"/*.json; do
  echo "Importing $(basename "$dashboard")..."
  
  PAYLOAD=$(jq '{"dashboard": (. | .id = null), "overwrite": true}' "$dashboard")
  
  curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
    -u "$USER:$PASSWORD" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"
    
  echo "" 
done