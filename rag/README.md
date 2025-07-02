# Overview

Simple example of a RAG system using Python, Ollama, LangChain, LangGraph, and LangSmith. Project dependencies are handled via poetry.

For a full writeup and walkthrough, check out the companion blog post at: https://www.blackhillsinfosec.com/avoiding-dirty-rags/

# Usage

I suggest using a system with Ubuntu 24.04 LTS and an NVIDIA GPU.

## Install CUDA Drivers

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt install -y gcc g++ cuda-toolkit nvidia-open
```

## Install Ollama and Pull Models
Note that the sleeps are in case you are pasting in these blocks all at once. You've got to give time for the Ollama oven to preheat.

```bash
curl -fsSL https://ollama.com/install.sh | sh
sleep 30
ollama pull BlackHillsInfoSec/llama-3.1-8b-abliterated
sleep 10
ollama pull mxbai-embed-large
```

## Install Conda and set Default Conda Environment as ollama-rag (Python 3.11)

```bash
mkdir -p ~/miniconda3 
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh 
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3 
rm ~/miniconda3/miniconda.sh 
source ~/miniconda3/bin/activate
conda init --all
conda create -y -n ollama-rag python=3.11
conda activate ollama-rag
echo "conda activate ollama-rag" >> ~/.bashrc
```

## Clone Repo and Install Dependencies with Poetry

```bash
pip install poetry
git clone https://github.com/fullmetalcache/TheHillsHaveAIs
cd TheHillsHaveAIs/rag
poetry install
```

## LangSmith

If you want LangSmith telemetry, you just need to create a LangSmith project, generate an API key, grab the environment variables, and set those environment variables in your shell before running the program. It's all free and easy to do.

https://smith.langchain.com

The companion blog post for this project also has full instructions on doing that. I highly recommend it.

## Run it!

```bash
cd rag
python3 main.py
```
