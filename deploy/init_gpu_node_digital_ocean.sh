#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- Starting the installation and monitoring setup ---"

# --- Define Core Variables ---
# Centralizing variables makes the script easier to manage.
HOME_DIR="$HOME"
USER_NAME="$(whoami)"
MINICONDA_DIR="$HOME_DIR/miniconda3"
LLM_PROJECT_DIR="$HOME_DIR/llmplayground"
MONITOR_PROJECT_DIR="$HOME_DIR/inactivity_monitor"
CONDA_ENV_NAME="llmplayground"

echo "User: $USER_NAME"
echo "Home Directory: $HOME_DIR"

# --- Install NVIDIA CUDA Drivers for GPU Support ---
# This section uses the official NVIDIA CUDA repository for reliability.
# It assumes a Debian-based Linux distribution (like Ubuntu) on x86_64 architecture.
echo "--- Installing NVIDIA CUDA Drivers ---"
# Update package lists and install prerequisites
sudo apt-get update
sudo apt-get install -y software-properties-common ca-certificates curl

# Download and install the NVIDIA repository GPG key and add the repository
# This is the official and most stable method.
curl -fSsL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nvidia-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /" | sudo tee /etc/apt/sources.list.d/nvidia-cuda.list > /dev/null

# Update the package list again to include the new NVIDIA repository
sudo apt-get update

# Install the recommended CUDA driver package
sudo apt-get install -y cuda-drivers

# --- Install Miniconda ---
echo "--- Installing Miniconda ---"
mkdir -p "$MINICONDA_DIR"
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$MINICONDA_DIR/miniconda.sh"
bash "$MINICONDA_DIR/miniconda.sh" -b -u -p "$MINICONDA_DIR"
rm "$MINICONDA_DIR/miniconda.sh"

# --- Initialize Conda for Script and Shell ---
echo "--- Initializing Conda ---"
# Source conda's script to make the `conda` command available for this script's execution.
source "$MINICONDA_DIR/etc/profile.d/conda.sh"
# `conda init` modifies shell startup files (e.g., .bashrc) for future interactive shells.
conda init --all

# --- Create Conda Environment and Install All Dependencies ---
echo "--- Creating '$CONDA_ENV_NAME' environment with all dependencies ---"
conda create -y -n "$CONDA_ENV_NAME" python=3.11
conda activate "$CONDA_ENV_NAME"

# --- Configure Auto-Activation for New Terminals ---
echo "--- Configuring automatic environment activation ---"
echo "conda activate $CONDA_ENV_NAME" >> "$HOME_DIR/.bashrc"

# --- Install Ollama and Pull Models ---
echo "--- Installing Ollama ---"
# The official installer script also creates and enables the ollama.service.
curl -fsSL https://ollama.com/install.sh | sh

# --- Setup Open-WebUI Poetry Project ---
echo "--- Setting up Open-WebUI with Poetry ---"
mkdir -p "$LLM_PROJECT_DIR"
cd "$LLM_PROJECT_DIR"
pip install poetry
poetry init --python ">=3.11,<3.13" --no-interaction
poetry add open-webui pydo requests watchdog
cd # Return to home directory

# --- Create the Inactivity Monitor Python Script ---
echo "--- Creating the inactivity monitor script ---"
mkdir -p "$MONITOR_PROJECT_DIR"

# This `heredoc` writes the Python code into the specified file.
# Note the changes in the `if __name__ == "__main__"` block to accept command-line arguments.
tee "$MONITOR_PROJECT_DIR/monitor_inactivity.py" > /dev/null <<'EOF'
import time
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import logging
import sys
import os
from pydo import Client
import requests

class ChangeHandler(FileSystemEventHandler):
    def __init__(self, timeout=28800, action=None):
        self.last_change = time.time()
        self.timeout = timeout
        self.action = action
        self.timer_running = False

    def on_any_event(self, event):
        # Ignore directory modifications to avoid loops on log file writes, etc.
        if event.is_directory:
            return

        self.last_change = time.time()
        logging.info(f"Change detected: {event.src_path} - {event.event_type}")

    def check_inactivity(self):
        while True:
            time_since_change = time.time() - self.last_change
            
            # Optional: More detailed logging for debugging.
            # logging.info(f"Time since last change: {time_since_change:.2f} seconds. Timeout is {self.timeout}s.")

            if time_since_change >= self.timeout:
                logging.info(f"No changes detected for {self.timeout} seconds, executing action.")
                if self.action:
                    try:
                        self.action()
                    except Exception as e:
                        logging.error(f"Error executing action: {e}")
                # Exit after action is called to prevent the service from restarting and destroying again.
                break 
            
            time.sleep(60)


def get_droplet_id():
    """Fetches the droplet ID from the DigitalOcean metadata service."""
    try:
        response = requests.get("http://169.254.169.254/metadata/v1/id", timeout=5)
        response.raise_for_status() # Raises an HTTPError for bad responses
        return response.text
    except requests.exceptions.RequestException as e:
        logging.error(f"Could not contact metadata service: {e}")
        return None

def monitor_directory(path, timeout, action=None):
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        handlers=[
            logging.FileHandler(f"{os.path.expanduser('~')}/inactivity_monitor.log"),
            logging.StreamHandler(sys.stdout)
        ]
    )

    path = Path(path).resolve()
    if not path.exists() or not path.is_dir():
        logging.error(f"Error: Directory not found or is not a directory: {path}")
        raise FileNotFoundError(f"Directory not found: {path}")

    event_handler = ChangeHandler(timeout=timeout, action=action)
    observer = Observer()
    observer.schedule(event_handler, str(path), recursive=True)

    try:
        observer.start()
        logging.info(f"Started monitoring {path} for inactivity.")
        event_handler.check_inactivity() # This runs in the main thread until the action is triggered.
    except KeyboardInterrupt:
        logging.info("Monitoring stopped by user.")
    finally:
        observer.stop()
        observer.join()
        logging.info("Observer terminated cleanly.")


def inactivity_action():
    logging.info("INACTIVITY ACTION: Deleting droplet now.")

    # It's crucial that the DIGITALOCEAN_TOKEN is available as an environment variable
    # for the systemd service.
    do_token = os.environ.get("DIGITALOCEAN_TOKEN")
    if not do_token:
        logging.error("FATAL: DIGITALOCEAN_TOKEN environment variable not set. Cannot destroy droplet.")
        sys.exit(1)

    droplet_id = get_droplet_id()
    if droplet_id is None:
        logging.error("Failed to get droplet ID. Aborting destruction.")
    else:
        logging.info(f"Destroying droplet with ID: {droplet_id}")
        try:
            client = Client(token=do_token)
            resp = client.droplets.destroy(droplet_id=droplet_id)
            logging.info(f"API call to destroy droplet sent. Response: {resp}")
        except Exception as e:
            logging.error(f"An error occurred during droplet destruction: {e}")
    
    sys.exit(0)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("ERROR: You must provide the directory path to monitor.", file=sys.stderr)
        print(f"Usage: python {sys.argv[0]} <directory_to_monitor>", file=sys.stderr)
        sys.exit(1)

    directory_to_watch = sys.argv[1]
    
    # The timeout is set via an environment variable or defaults to 28800 (8 hours).
    inactivity_timeout = int(os.environ.get('INACTIVITY_TIMEOUT', 28800))
    
    monitor_directory(path=directory_to_watch, timeout=inactivity_timeout, action=inactivity_action)
EOF

# --- Dynamically Find Web UI Path ---
echo "--- Finding Open-WebUI package path ---"
# This command runs Python inside the conda env to find the library path
# and saves it to a bash variable. This is the key to making the script portable.
WEBUI_PATH=$(conda run -n "$CONDA_ENV_NAME" python -c "import open_webui, os; print(os.path.dirname(open_webui.__file__))")
echo "Open-WebUI found at: $WEBUI_PATH"

# --- Create and Enable Systemd Services ---
echo "--- Creating and enabling systemd services ---"

# Service for Open-WebUI
# This service will now wait for the Ollama service to be active.
sudo tee /etc/systemd/system/open-webui.service > /dev/null <<EOF
[Unit]
Description=Open-WebUI Application
# Ensures that Open-WebUI starts after Ollama is running.
After=network.target ollama.service

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$LLM_PROJECT_DIR
# Use `conda run` to execute the command in the correct environment.
ExecStart=$MINICONDA_DIR/bin/conda run -n $CONDA_ENV_NAME open-webui serve --host 127.0.0.1 --port 4141
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Service for the Inactivity Monitor
# IMPORTANT: You must set the DIGITALOCEAN_TOKEN for this service to work.
sudo tee /etc/systemd/system/inactivity-monitor.service > /dev/null <<EOF
[Unit]
Description=Inactivity monitor for self-destruction
After=open-webui.service

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$MONITOR_PROJECT_DIR

# Set environment variables for the service here.
# The token MUST be provided for the script to work.
# You can also override the default 8-hour timeout.
Environment="DIGITALOCEAN_TOKEN=<INSERT DO KEY HERE>"
Environment="INACTIVITY_TIMEOUT=28800"

# `conda run` ensures the script uses the right python and libraries.
# The dynamically found WEBUI_PATH is passed as an argument.
ExecStart=$MINICONDA_DIR/bin/conda run --no-capture-output -n $CONDA_ENV_NAME python $MONITOR_PROJECT_DIR/monitor_inactivity.py $WEBUI_PATH
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# --- Final Steps ---
echo "--- Reloading systemd and starting services ---"

# Reload the systemd daemon to recognize the new service files.
sudo systemctl daemon-reload

# Enable all services to start on boot.
# The Ollama installer should do this, but we run it to be safe.
sudo systemctl enable ollama.service
sudo systemctl enable open-webui.service
sudo systemctl enable inactivity-monitor.service

# Start all services immediately.
sudo systemctl start ollama.service
sudo systemctl start open-webui.service
sudo systemctl start inactivity-monitor.service

echo "--- Pulling Ollama Models ---"

# 42GB - huihui_ai/deepseek-r1-abliterated:70b
ollama pull huihui_ai/deepseek-r1-abliterated:70b

# 19GB - huihui_ai/qwen3-abliterated:32b
ollama pull huihui_ai/qwen3-abliterated:32b

# 8GB - superdrew100/phi3-medium-abliterated:latest
ollama pull superdrew100/phi3-medium-abliterated:latest

# 42GB - huihui_ai/llama3.3-abliterated:70b
ollama pull huihui_ai/llama3.3-abliterated:70b

# 17GB - pidrilkin/gemma3_27b_abliterated:Q4_K_M
ollama pull pidrilkin/gemma3_27b_abliterated:Q4_K_M

# 14GB - huihui_ai/mistral-small-abliterated:24b
ollama pull huihui_ai/mistral-small-abliterated:24b

# 9GB - huihui_ai/phi4-abliterated:14b
ollama pull huihui_ai/phi4-abliterated:14b

# 9GB - jaahas/qwen3-abliterated:14b
ollama pull jaahas/qwen3-abliterated:14b

echo "--- Installation and setup complete! ---"
echo "Services 'ollama', 'open-webui', and 'inactivity-monitor' have been started."
echo "To check their status, run:"
echo "sudo systemctl status ollama.service"
echo "sudo systemctl status open-webui.service"
echo "sudo systemctl status inactivity-monitor.service"
echo "To see the monitor's log, run:"
echo "tail -f $HOME/inactivity_monitor.log"
echo "To use the '$CONDA_ENV_NAME' environment in your terminal, please run: source ~/.bashrc"

