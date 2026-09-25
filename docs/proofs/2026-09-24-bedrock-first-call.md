# Bedrock first call (Task 7, Step 1)

Time (UTC): 2026-09-25T00:05:49Z

Command:

```bash
aws bedrock-runtime converse --profile cohack --region us-east-1 \
  --model-id qwen.qwen3-coder-30b-a3b-v1:0 \
  --messages '[{"role":"user","content":[{"text":"Reply with the single word ready."}]}]' \
  --query 'output.message.content[0].text' --output text
```

Output:

```
ready
```

Model access for the Qwen models was already granted in the member account (us-east-1); no console
step was needed.
