# Local LLM Setup for Fridge App

This guide will help you set up a local LLM (Large Language Model) to predict expiry dates for food items in your Fridge app.

## Prerequisites

- Docker installed on your system
- At least 4GB of available RAM
- Internet connection for initial model download

## Quick Setup with Ollama

### 1. Install Ollama

**Windows:**
```bash
# Download and install from https://ollama.ai/download
# Or use winget:
winget install Ollama.Ollama
```

**macOS:**
```bash
# Download and install from https://ollama.ai/download
# Or use Homebrew:
brew install ollama
```

**Linux:**
```bash
curl -fsSL https://ollama.ai/install.sh | sh
```

### 2. Start Ollama Service

**For Desktop Development:**
```bash
ollama serve
```

**For Mobile Development (required for physical devices):**
```bash
# Windows PowerShell
$env:OLLAMA_HOST="0.0.0.0:11434"
ollama serve

# Linux/macOS
export OLLAMA_HOST=0.0.0.0:11434
ollama serve
```

This will start the Ollama server accessible from other devices on your network.

### 3. Download a Lightweight Model

For mobile use, we recommend a smaller, faster model:

```bash
# Download Llama 3.2 3B (recommended - ~2GB)
ollama pull llama3.2:3b

# Alternative: Download Phi-3 Mini (even smaller - ~2.3GB)
ollama pull phi3:mini

# Alternative: Download Gemma 2B (smallest - ~1.6GB)
ollama pull gemma:2b
```

### 4. Find Your Computer's IP Address

**Windows:**
```cmd
ipconfig
```

**macOS/Linux:**
```bash
ifconfig
# or
ip addr
```

Look for your Wi-Fi adapter's IPv4 address (e.g., `10.0.0.218`).

### 5. Test the Setup

Verify that Ollama is working:

```bash
# Test from your computer
curl http://localhost:11434/api/tags

# Test from your computer's IP (for mobile access)
curl http://YOUR_IP_ADDRESS:11434/api/tags
```

### 6. Configure the Fridge App

Update the LLM service configuration in `lib/services/llm_service.dart`:

```dart
// Replace with your computer's IP address
static const String _baseUrl = 'http://YOUR_IP_ADDRESS:11434';

// Use your available model
static const String _model = 'llama2-uncensored:latest';
```

**Current configuration for this setup:**
- IP Address: `10.0.0.218`
- Model: `llama2-uncensored:latest`

## Alternative: Using Different Models

### For Better Accuracy (requires more resources):

```bash
# Llama 3.2 8B (better accuracy, ~4.7GB)
ollama pull llama3.2:8b

# Llama 3.1 8B (alternative)
ollama pull llama3.1:8b
```

### For Maximum Speed (lower accuracy):

```bash
# TinyLlama 1.1B (very fast, ~637MB)
ollama pull tinyllama:1.1b

# Qwen2.5 1.5B (good balance)
ollama pull qwen2.5:1.5b
```

## Troubleshooting

### Ollama Not Starting
- Make sure no other service is using port 11434
- Check if Docker is running (Ollama uses Docker for models)
- Try restarting your computer

### Model Not Found
```bash
# List available models
ollama list

# If your model isn't there, pull it again
ollama pull llama3.2:3b
```

### Connection Refused
- Ensure Ollama is running: `ollama serve`
- Check if the service is accessible: `curl http://localhost:11434/api/tags`
- On mobile devices, make sure your device can reach your computer's IP address

### Performance Issues
- Use a smaller model (3B or less)
- Close other applications to free up RAM
- Consider using a more powerful computer for the LLM server

## Mobile Development Setup

For mobile development, you'll need to make the LLM accessible from your mobile device:

### Option 1: Use Computer's IP Address
1. Find your computer's IP address:
   - Windows: `ipconfig`
   - macOS/Linux: `ifconfig` or `ip addr`
2. Update the LLM service URL in `lib/services/llm_service.dart`:
   ```dart
   static const String _baseUrl = 'http://YOUR_IP_ADDRESS:11434';
   ```

### Option 2: Use ngrok (for testing)
```bash
# Install ngrok
# Create tunnel to Ollama
ngrok http 11434
# Use the ngrok URL in your app
```

## Security Notes

- The LLM runs locally on your machine
- No data is sent to external servers
- All predictions are processed offline
- Keep your Ollama server behind a firewall in production

## Performance Tips

1. **Use SSD storage** for faster model loading
2. **Allocate sufficient RAM** (4GB+ recommended)
3. **Use a smaller model** for mobile development
4. **Enable GPU acceleration** if available (requires NVIDIA GPU and CUDA)

## Model Comparison

| Model | Size | Speed | Accuracy | RAM Usage |
|-------|------|-------|----------|-----------|
| llama3.2:3b | ~2GB | Fast | Good | ~4GB |
| phi3:mini | ~2.3GB | Fast | Good | ~4GB |
| gemma:2b | ~1.6GB | Very Fast | Fair | ~3GB |
| tinyllama:1.1b | ~637MB | Very Fast | Fair | ~2GB |

## Next Steps

Once Ollama is running with a model, your Fridge app will automatically:
- Predict expiry dates for manually added items
- Predict expiry dates for scanned items
- Categorize items by grocery type
- Fall back to rule-based predictions if LLM is unavailable

The app will show an AI icon (✨) in the status bar when the LLM is available and working.

