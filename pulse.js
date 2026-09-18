#!/usr/bin/env python3
import sys
import json
import re

def reflect_stimuli(text):
    # Regex dictionary for requested multidimensional data types
    patterns = {
        "hex": r"\b0[xX][0-9a-fA-F]+\b",
        "octal": r"\b0[oO][0-7]+\b",
        "imaginary": r"\b[-+]?(?:\d*\.\d+|\d+)[ij]\b",
        "real": r"\b[-+]?(?:\d+\.\d*|\.\d+)(?:[eE][-+]?\d+)?(?![ij])\b",
        "decimal": r"\b(?<!\.)(?:0|[1-9]\d*)(?!\.)\b(?!\s*[ij])",
        "degree": r"\b\d+(?:\.\d+)?(?:°|deg)\b",
        "kinetics": r"\b(kin|pot)\b",
        "tags": r"\b(real|imag|octal|hex|dec|degree)\b"
    }

    extracted = {}
    for key, pattern in patterns.items():
        matches = re.findall(pattern, text, flags=re.IGNORECASE)
        if matches:
            extracted[key] = matches

    # Construct the validated AI Prompt wrapper
    safe_prompt = (
        "=== STIMULI PARSER INITIATED ===\n"
        f"Raw Text: {text}\n"
        f"Extracted Nodes: {json.dumps(extracted, indent=2)}\n"
        "Directive: Analyze the parsed mathematical and conceptual stimuli. Establish connections between the nodes."
    )

    return {
        "valid": bool(text.strip()),
        "original": text,
        "nodes": extracted,
        "ai_prompt": safe_prompt
    }

if __name__ == "__main__":
    raw_input = sys.argv[1] if len(sys.argv) > 1 else ""
    # Output strictly valid JSON for Node.js to consume
    print(json.dumps(reflect_stimuli(raw_input)))
