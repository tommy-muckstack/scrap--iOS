# OpenAI API Key Setup

## For Development (Xcode)

1. In Xcode, go to your project settings
2. Select your target → Build Settings
3. Search for "User-Defined"
4. Add a new User-Defined setting:
   - Key: `OPENAI_API_KEY`
   - Value: Your OpenAI API key (starts with `sk-`)

## Alternative: Environment Variable

Add to your shell profile (~/.zshrc or ~/.bash_profile):
```bash
export OPENAI_API_KEY="your-api-key-here"
```

## For Production

Never commit API keys to the repository. Use:
- Xcode build configurations
- Environment variables
- Secure key management services

## Getting Your API Key

1. Visit https://platform.openai.com/api-keys
2. Create a new secret key
3. Copy the key and configure as above

## Notes

- The app will work without the API key (titles won't be generated)
- Only GPT-3.5-turbo is used for cost efficiency
- Title generation is limited to 20 tokens maximum