#!/usr/bin/env python3
"""
gemini_crud.py - SKILL.md Compliant API Bridge
Uses the Gemini Interactions API for remote task execution.
"""
import sys
import json
import os
import traceback

try:
    from google import genai
except ImportError:
    print(json.dumps({"error": "google-genai >= 2.3.0 is not installed."}))
    sys.exit(1)

def main():
    # Read prompt from STDIN via Bash orchestrator
    prompt = sys.stdin.read().strip()
    if not prompt:
        print(json.dumps({"error": "Empty prompt received."}))
        sys.exit(1)

    try:
        # Client automatically picks up GEMINI_API_KEY from environment
        client = genai.Client()
        
        # Following SKILL.md rules: Using recommended general model
        interaction = client.interactions.create(
            model="gemini-3.7-flash",
            input=prompt
        )
        
        # Format for Bash Orchestrator ingestion
        output_data = {
            "status": "success",
            "model": "gemini-3.7-flash",
            "output": interaction.output_text,
            "interaction_id": interaction.id
        }
        
        print(json.dumps(output_data))
        
    except Exception as e:
        error_payload = {
            "status": "failed",
            "error": str(e),
            "trace": traceback.format_exc()
        }
        print(json.dumps(error_payload))
        sys.exit(1)

if __name__ == "__main__":
    main()
