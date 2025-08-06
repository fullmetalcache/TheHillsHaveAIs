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
# Need to accept ToS now before installing
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
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
ExecStart=$MINICONDA_DIR/bin/conda run -n $CONDA_ENV_NAME open-webui serve --host 127.0.0.1 --port 4242
Restart=on-failure
RestartSec=5

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

# Start all services immediately.
sudo systemctl start ollama.service
sudo systemctl start open-webui.service

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
echo "Services 'ollama' and 'open-webui' have been started."
echo "To check their status, run:"
echo "sudo systemctl status ollama.service"
echo "sudo systemctl status open-webui.service"
echo "To use the '$CONDA_ENV_NAME' environment in your terminal, please run: source ~/.bashrc"
