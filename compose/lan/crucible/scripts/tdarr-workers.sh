#!/bin/bash
# Set Tdarr GPU workers after container startup
# Workers are runtime-only state and reset to 0 on restart

for i in {1..30}; do
  if curl -s http://localhost:8266/api/v2/get-nodes | grep -q nodeID 2>/dev/null; then
    break
  fi
  sleep 2
done

NODE_ID=$(curl -s http://localhost:8266/api/v2/get-nodes | python3 -c "import sys,json; print(list(json.load(sys.stdin).keys())[0])" 2>/dev/null)
if [ -z "$NODE_ID" ]; then
  echo "Could not get Tdarr node ID"
  exit 1
fi

# 3 GPU transcode (maxes out RTX 3060 NVENC), 2 GPU healthcheck
for i in 1 2 3; do
  curl -s -X POST http://localhost:8266/api/v2/alter-worker-limit \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"nodeID\":\"$NODE_ID\",\"process\":\"increase\",\"workerType\":\"transcodegpu\"}}" > /dev/null
done
for i in 1 2; do
  curl -s -X POST http://localhost:8266/api/v2/alter-worker-limit \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"nodeID\":\"$NODE_ID\",\"process\":\"increase\",\"workerType\":\"healthcheckgpu\"}}" > /dev/null
done

echo "Tdarr workers configured: 3 GPU transcode, 2 GPU healthcheck"
