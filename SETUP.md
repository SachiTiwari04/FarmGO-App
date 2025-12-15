# 🚀 FarmGo App - Setup Instructions

## Prerequisites
- Flutter SDK 3.0+
- Android Studio / VS Code
- Firebase project
- Google Cloud project with APIs enabled

## First Time Setup

### 1. Clone the Repository
\`\`\`bash
git clone https://github.com/SachiTiwari04/FarmGO-App.git
cd farm_go_app
\`\`\`

### 2. Install Dependencies
\`\`\`bash
flutter pub get
\`\`\`

### 3. Configure Environment Variables
\`\`\`bash
# Copy the example file
cp .env.example .env

# Edit .env and add your API keys
# Use nano, vim, or any text editor
nano .env
\`\`\`

Required API keys:
- **GEMINI_API_KEY**: Get from [Google AI Studio](https://makersuite.google.com/app/apikey)
- **GOOGLE_MAPS_API_KEY**: Get from [Google Cloud Console](https://console.cloud.google.com/apis/credentials)

### 4. Firebase Setup
1. Download `google-services.json` from Firebase Console
2. Place it in `android/app/google-services.json`
3. Ensure it's listed in `.gitignore`

### 5. Enable Required APIs
In Google Cloud Console, enable:
- Generative Language API (for Gemini)
- Maps SDK for Android
- Places API
- Geocoding API

### 6. Run the App
\`\`\`bash
flutter run
\`\`\`

## Troubleshooting

### "GEMINI_API_KEY not found"
- Make sure `.env` file exists in project root
- Check that the key name matches exactly: `GEMINI_API_KEY`
- Run `flutter clean` and `flutter pub get`

### Map not loading
- Check Google Maps API key in `AndroidManifest.xml`
- Enable required APIs in Google Cloud Console
- Check billing is enabled

### Build errors
\`\`\`bash
flutter clean
flutter pub get
flutter run
\`\`\`

## Project Structure
\`\`\`
farm_go_app/
├── .env                    # ❌ Never commit (local only)
├── .env.example            # ✅ Commit (template)
├── .gitignore              # ✅ Commit
├── SETUP.md                # ✅ Commit (this file)
├── README.md               # ✅ Commit
├── lib/
│   ├── main.dart
│   ├── firebase_services.dart
│   └── ...
└── android/
    └── app/
        ├── google-services.json  # ❌ Never commit
        └── ...
\`\`\`

## Security Notes
- Never commit `.env` or `google-services.json`
- Rotate API keys if accidentally exposed
- Use API restrictions in Google Cloud Console
- Enable billing alerts