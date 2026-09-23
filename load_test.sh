#!/bin/bash

# Target the public IP of  vllm-service
VLLM_IP="66.201.4.188"
TOTAL_BATCHES=100
CONCURRENCY=20

echo "Starting synthetic load test against http://${VLLM_IP}..."

send_request() {
  local model=$1
  local prompt=$2

  curl -s -X POST "http://${VLLM_IP}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "'"$model"'",
      "messages": [{"role": "user", "content": "'"$prompt"'"}],
      "max_tokens": 128,
      "temperature": 0.7
    }' > /dev/null
}

for batch in $(seq 1 $TOTAL_BATCHES); do
  echo "Firing Batch $batch of $TOTAL_BATCHES ($((CONCURRENCY * 2)) parallel requests)..."
  
  for i in $(seq 1 $CONCURRENCY); do
    # Parallel requests to Base model
    send_request "Qwen/Qwen2.5-Coder-7B-Instruct" \
      "Explain the architectural trade-offs between monolithic and microservice architectures." &
    
    # Parallel requests to LoRA adapter
    send_request "sql-expert-lora" \
      "Schema: table sales (id int, amount decimal, user_id int). Question: Find total sales per user." &
  done

  # Wait for current batch to flush
  wait
  sleep 1
done
echo "Load test completed."