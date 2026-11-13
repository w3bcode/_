#!/bin/bash

export AI_VERBOSE=1
export AI_STREAM=1
export AI_TOKEN_TRACE=1
export AI_HASH_TRACE=1
export AI_EVENT_TRACE=1
export AI_MAX_CONTEXT=4096

exit

alias agi='llama-cli -m ~/.ai/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf --prompt "$1"'
