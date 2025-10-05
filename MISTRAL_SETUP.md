# Mistral AI Setup Guide

This project has been updated to use Mistral AI instead of the local Ollama setup.

## Environment Configuration

### Option 1: Compile-Time Environment Variable (Recommended)
Set the Mistral AI API key as a compile-time environment variable:

**Windows (PowerShell):**
```powershell
$env:MISTRAL_API_KEY="jUqF4Ky239HiTm469aC3U2iH1D06nwAf"
flutter run
```

**Windows (Command Prompt):**
```cmd
set MISTRAL_API_KEY=jUqF4Ky239HiTm469aC3U2iH1D06nwAf
flutter run
```

**Linux/macOS:**
```bash
export MISTRAL_API_KEY="jUqF4Ky239HiTm469aC3U2iH1D06nwAf"
flutter run
```

### Option 2: Fallback Configuration
The API config includes a fallback key in the code for development purposes.

## Model Configuration

- **Model**: `mistral-large-latest`
- **Provider**: Mistral AI
- **Base URL**: `https://api.mistral.ai/v1`

## Features

The updated LLM service provides:

1. **Food Expiry Prediction**: Predicts days until expiry for food items
2. **Grocery Type Classification**: Classifies items into categories (dairy, meat, vegetables, etc.)
3. **Recipe Generation**: Generates recipes based on available ingredients
4. **Service Availability Check**: Verifies Mistral AI service connectivity

## API Usage

The service automatically handles:
- Authentication with Mistral AI API
- Request formatting for chat completions
- Response parsing and error handling
- Timeout management

## Testing

To test the integration:

1. Ensure the API key is set (environment variable or fallback)
2. Run the app and use features that require LLM:
   - Food scanning and expiry prediction
   - Recipe generation
3. Check console logs for any API errors

## Migration from Ollama

The following changes were made:
- Replaced Ollama server connection with Mistral AI API calls
- Updated request format to OpenAI-compatible chat completions
- Changed model from `llama3.2:3b` to `mistral-large-latest`
- Added proper authentication headers
- Updated timeout and error handling

## Troubleshooting

**Common Issues:**

1. **API Key Invalid**: Verify the key is correct and has sufficient credits
2. **Network Errors**: Check internet connectivity
3. **Model Unavailable**: Verify the model name is correct
4. **Rate Limits**: Mistral AI may have rate limits; check their documentation

**Debug Information:**
- Check console logs for detailed error messages
- Use `LLMService().isAvailable()` to test connectivity
- Monitor API response codes and error messages

## Security Notes

- **API keys are set via compile-time environment variables** for security
- **Fallback key is included** for development purposes
- **No runtime file loading** eliminates encoding issues
- **Environment variables are not stored** in version control

## Files Created/Modified

- `lib/config/api_config.dart` - Updated to use compile-time constants
- `lib/main.dart` - Removed dotenv initialization
- `lib/services/llm_service.dart` - Updated to use Mistral AI
- `pubspec.yaml` - Removed flutter_dotenv dependency
