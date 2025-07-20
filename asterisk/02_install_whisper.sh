#!/bin/bash
set -e

cd ~

# ----- Clone or Update whisper.cpp -----
if [ ! -d whisper.cpp ]; then
  echo "📁 Cloning whisper.cpp..."
  git clone https://github.com/ggerganov/whisper.cpp.git
else
  echo "🔄 Updating whisper.cpp..."
  cd whisper.cpp
  git pull
  cd ..
fi

cd ~/whisper.cpp

# ----- Build whisper.cpp -----
if [ ! -f build/bin/main ]; then
  echo "🔨 Building whisper.cpp (first attempt)..."
  cmake -B build
  cmake --build build --config Release
fi

# ----- Verify Binaries -----
if [ -f build/bin/whisper-cli ]; then
  ln -sf build/bin/whisper-cli whisper-cli
  ln -sf build/bin/main whisper
  SUMMARY["Whisper"]="✅ Built"
  echo "✅ whisper binaries set up"
else
  echo "❗ Failed to build whisper.cpp – retrying..."
  make || cmake --build build --config Release
  if [ -f build/bin/whisper-cli ]; then
    ln -sf build/bin/whisper-cli whisper-cli
    ln -sf build/bin/main whisper
    SUMMARY["Whisper"]="✅ Built (retry)"
    echo "✅ whisper binaries set up after retry"
  else
    SUMMARY["Whisper"]="❌ Build failed"
    echo "⚠️ whisper build failed twice. Check errors above."
  fi
fi

# ----- Download Whisper Models -----
echo "⬇️ Preparing to download Whisper models..."
cd ~/whisper.cpp

if [ -d models ]; then
  echo "📂 'models' directory already exists. Listing contents:"
  ls -lh models
else
  echo "📁 Creating 'models' directory..."
  mkdir models
fi

cd models

declare -A WHISPER_MODELS=(
  ["ggml-base.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
  ["ggml-small.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
  ["ggml-medium.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
  ["ggml-large-v3.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
)

ALL_OK=true
for model in "${!WHISPER_MODELS[@]}"; do
  if [ -f "$model" ]; then
    echo "✅ $model already exists (size: $(du -h "$model" | cut -f1))"
  else
    echo "📦 Downloading $model..."
    if curl -fLO "${WHISPER_MODELS[$model]}"; then
      echo "✅ $model downloaded"
    else
      echo "❌ Failed to download $model"
      ALL_OK=false
    fi
  fi
done

cd ..

SUMMARY["Models"]=$([ "$ALL_OK" = true ] && echo "✅ All present" || echo "⚠️ Some missing")

# ----- Install Binaries Globally -----
if [ -f build/bin/main ]; then
  echo "🔗 Installing whisper to /usr/local/bin"
  sudo install -m 755 build/bin/main /usr/local/bin/whisper
  echo "✅ whisper installed globally"
else
  echo "❌ whisper binary not found at build/bin/main"
fi

if [ -f build/bin/whisper-cli ]; then
  echo "🔗 Installing whisper-cli to /usr/local/bin"
  sudo install -m 755 build/bin/whisper-cli /usr/local/bin/whisper-cli
  echo "✅ whisper-cli installed globally"
else
  echo "❌ whisper-cli binary not found at build/bin/whisper-cli"
fi
