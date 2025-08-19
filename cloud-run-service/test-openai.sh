#!/bin/bash

echo "Testing OpenAI API Integration..."
echo ""

# Test OpenAI API directly
echo "1. Testing OpenAI API key validity..."
curl -s -X POST "https://api.openai.com/v1/chat/completions" \
  -H "Authorization: Bearer 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" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {
        "role": "user",
        "content": "Hello! This is a test message."
      }
    ],
    "max_tokens": 50
  }' | jq .

echo ""
echo "OpenAI API test completed!" 