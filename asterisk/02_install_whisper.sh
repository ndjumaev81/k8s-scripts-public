#!/bin/bash
set -e

cd ~
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

# Try building, and fallback if needed
if [ ! -f build/main ]; then
  echo "🔨 Building whisper.cpp (first attempt)..."
  cmake -B build
  cmake --build build --config Release
fi

# ensure whisper executable exists
if [ -f build/bin/whisper-cli ]; then
  ln -sf build/bin/whisper-cli whisper-cli
  ln -sf build/bin/main whisper
  SUMMARY["Whisper"]="✅ Built"
  echo "✅ whisper binaries set up"
else
  echo "❗ Failed to build whisper.cpp – retrying..."
  cd ~/whisper.cpp
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

# ----- Models Download -----
echo "⬇️ Downloading Whisper models..."
mkdir -p models
cd models
ALL_OK=true
for model in base small medium large; do
  FILE="ggml-${model}.bin"
  if [ ! -f "$FILE" ]; then
    curl -fsSL -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$FILE || ALL_OK=false
  fi
done


echo "⬇️ Downloading Whisper models..."

mkdir -p models
cd models

declare -A WHISPER_MODELS=(
  ["ggml-base.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
  ["ggml-small.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
  ["ggml-medium.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
  ["ggml-large-v3.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
)

MODEL_STATUS=""

for model in "${!WHISPER_MODELS[@]}"; do
  if [ ! -f "$model" ]; then
    echo "📦 Downloading $model..."
    if curl -fLO "${WHISPER_MODELS[$model]}"; then
      echo "✅ $model downloaded"
    else
      echo "❌ Failed to download $model"
      MODEL_STATUS+=" ❌ $model "
    fi
  else
    echo "✅ $model already exists"
  fi
done

cd ..

SUMMARY["Models"]=$([ "$ALL_OK" = true ] && echo "✅ All present" || echo "⚠️ Some missing")

# ----- Install Binaries Globally -----
if [ -f ~/whisper.cpp/build/bin/whisper ]; then
  echo "🔗 Installing whisper to /usr/local/bin"
  sudo install -m 755 ~/whisper.cpp/build/bin/whisper /usr/local/bin/whisper
  echo "✅ whisper installed globally"
else
  echo "❌ whisper binary not found, skipping install"
fi

if [ -f ~/whisper.cpp/build/bin/whisper-cli ]; then
  echo "🔗 Installing whisper-cli to /usr/local/bin"
  sudo install -m 755 ~/whisper.cpp/build/bin/whisper-cli /usr/local/bin/whisper-cli
  echo "✅ whisper-cli installed globally"
else
  echo "❌ whisper-cli binary not found, skipping install"
fi
