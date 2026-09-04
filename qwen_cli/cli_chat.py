#!/bin/python3

import os
import sys
import argparse
from datetime import datetime
from llama_cpp import Llama
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from rich.live import Live

# Initialize Rich console output
console = Console()

def parse_arguments():
    """Defines and parses configurable runtime parameters from boot args."""
    parser = argparse.ArgumentParser(description="Qwen High-Performance Infinite-Context CLI Engine")
    
    parser.add_argument("-t", "--temperature", type=float, default=0.7,
                        help="Creativity control parameter (0.0 to 1.5). Default is 0.7.")
    parser.add_argument("-p", "--top-p", type=float, default=0.95,
                        help="Nucleus sampling threshold parameter. Default is 0.95.")
    parser.add_argument("-gl", "--gpu-layers", type=int, default=-1,
                        help="Layers to offload to GPU (-1 for all, 0 for CPU-only). Default is -1.")
    parser.add_argument("-ctx", "--context-window", type=int, default=4096,
                        help="Max sequence context memory length. Default is 4096.")
                        
    return parser.parse_args()

args = parse_arguments()

CONTEXT_CEILING = args.context_window
COMPRESSION_THRESHOLD = int(CONTEXT_CEILING * 0.85)

# Initialize local model with parsed arguments
with console.status(f"[bold green]Loading Qwen (GPU Layers: {args.gpu_layers}, Max Context: {CONTEXT_CEILING})...", spinner="dots"):
    try:
        llm = Llama(
            model_path="./qwen3-4b-instruct-q6_k.gguf",
            n_ctx=CONTEXT_CEILING,
            n_gpu_layers=args.gpu_layers, 
            verbose=False 
        )
    except Exception as e:
        console.print(f"[bold red]Initialization failure: Ensure the .gguf model file is in this directory.[/bold red]\nDetails: {e}")
        sys.exit(1)

def get_system_prompt():
    return "<|im_start|>system\nYou are a helpful AI assistant. Always use markdown formatting for code blocks or data tables.<|im_end|>\n"

messages = []

def build_chat_string(msg_list):
    buffer = get_system_prompt()
    for role, text in msg_list:
        buffer += f"<|im_start|>{role}\n{text}<|im_end|>\n"
    return buffer

def count_tokens(text_string):
    return len(llm.tokenize(bytes(text_string, encoding="utf-8")))

# Launch Dashboard UI
welcome_panel = (
    f"[bold cyan]Qwen Core Engine Active[/bold cyan]\n"
    f"🌡️ Temperature: [bold white]{args.temperature}[/bold white] | "
    f"🎯 Top-P: [bold white]{args.top-p}[/bold white] | "
    f"🧠 Max Context: [bold white]{CONTEXT_CEILING}[/bold white]\n\n"
    "[bold yellow]Terminal Commands:[/bold yellow]\n"
    " ➔ [bold white]/clear[/bold white]   - Wipe conversation buffer context\n"
    " ➔ [bold white]/save[/bold white]    - Export markdown session logs\n"
    " ➔ [bold white]/history[/bold white] - View structural sequence usage metrics\n"
    " ➔ [bold white]/exit[/bold white]    - Terminate CLI runtime environment safely"
)
console.print(Panel(welcome_panel, title="Hyper-Configured CLI Interface"))

while True:
    try:
        user_input = console.input("\n[bold green]You[/bold green] ➔ ").strip()
        if not user_input:
            continue

        # --- CLI SLASH COMMAND HANDLING ---
        if user_input.startswith("/"):
            command = user_input.lower()
            if command in ['/exit', '/quit']:
                console.print("[bold red]Core shutdown complete.[/bold red]")
                break
            elif command == '/clear':
                messages = []
                console.print("[bold yellow]🧹 Sequence context queue reset successfully.[/bold yellow]")
                continue
            elif command == '/save':
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = f"chat_log_{timestamp}.md"
                with open(filename, "w", encoding="utf-8") as f:
                    f.write(build_chat_string(messages))
                console.print(f"[bold green]💾 Markdown log saved to: [underline]{filename}[/underline][/bold green]")
                continue
            elif command == '/history':
                raw_ctx = build_chat_string(messages)
                current_tokens = count_tokens(raw_ctx)
                console.print(f"[bold blue]Tokens active: {current_tokens} / {CONTEXT_CEILING} max[/bold blue]")
                continue
            else:
                console.print("[bold red]❌ Command string matching failed.[/bold red]")
                continue

        # --- MANAGED AUTO-TRIM QUEUE ---
        messages.append(("user", user_input))
        current_ctx_string = build_chat_string(messages)
        total_tokens = count_tokens(current_ctx_string)

        while total_tokens > COMPRESSION_THRESHOLD and len(messages) > 2:
            messages.pop(0)
            messages.pop(0)
            current_ctx_string = build_chat_string(messages)
            total_tokens = count_tokens(current_ctx_string)
            console.print("[bold orange3]⚠️ Memory Window Alert: Oldest thread interaction dropped to maintain window.[/bold orange3]")

        # --- GENERATION STREAMING RUNTIME ---
        prompt_with_suffix = current_ctx_string + "<|im_start|>assistant\n"
        
        stream = llm(
            prompt_with_suffix,
            max_tokens=1024,
            temperature=args.temperature,
            top_p=args.top_p,
            stop=["<|im_end|>"],
            stream=True
        )

        assistant_response = ""
        console.print("[bold magenta]Assistant[/bold magenta] ➔ ", end="")
        
        with Live(Markdown(""), refresh_per_second=15, console=console) as live:
            for chunk in stream:
                text_chunk = chunk["choices"]["text"]
                assistant_response += text_chunk
                live.update(Markdown(assistant_response))

        messages.append(("assistant", assistant_response))

    except KeyboardInterrupt:
        console.print("\n[bold red]Runtime closed execution safely via Interruption Signal.[/bold red]")
        break
