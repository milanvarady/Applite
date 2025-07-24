# Building Applite - Developer Guide

> **📋 Note**: This guide focuses on building and developing Applite. For general contribution guidelines (reporting bugs, suggesting features), see [`CONTRIBUTING.md`](CONTRIBUTING.md).

This comprehensive guide explains how to build, test, and develop Applite using various environments and tools. Whether you're making a quick fix or preparing a release, this document covers automated GitHub Actions builds, local development workflows, and cloud-based development with GitHub Codespaces.

## Table of Contents

1. [Build Methods Overview](#build-methods-overview)
2. [GitHub Codespaces Development](#github-codespaces-development)
3. [Quick Start - Local Development](#quick-start---local-development)
4. [GitHub Actions Automated Builds](#github-actions-automated-builds)
5. [Local Manual Builds](#local-manual-builds)
6. [Running Unsigned Apps (Gatekeeper)](#running-unsigned-apps-gatekeeper)
7. [Code Signing Setup](#code-signing-setup)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Configuration](#advanced-configuration)

## Build Methods Overview

### �️ GitHub Codespaces (Recommended for Cross-Platform Contributors)
**Best for:** Contributors without macOS, remote development, quick contributions, cloud-based workflows

**Pros:**
- 💻 **Cross-platform access** - Develop from Windows, Linux, or any device with a browser
- ⚡ **Instant setup** - Pre-configured environment with dependencies
- 🔄 **Seamless GitHub integration** - Direct access to GitHub Actions and repository
- 💾 **Persistent environment** - Your setup saves between sessions
- 🌐 **Remote debugging** - Connect to macOS devices for testing
- 🔧 **IDE integration** - Full VS Code experience in the browser or desktop

**Cons:**
- 🖥️ **No direct macOS app testing** - Requires GitHub Actions or remote macOS device
- 💰 **Usage-based billing** - GitHub Codespaces minutes (generous free tier)
- 🌐 **Internet dependent** - Requires stable connection

**Perfect for:**
- Making code changes and using GitHub Actions for building
- Documentation and configuration updates  
- Debugging build scripts and automation
- Contributing without owning a Mac

### 🏠 Local Development (Recommended for Mac Users)
**Best for:** Daily development, debugging, quick iterations, testing changes

**Pros:**
- ⚡ **Instant feedback and debugging**
- 🔧 **Full Xcode tooling** (Interface Builder, debugger, profiler)
- 💻 **Uses your local environment and preferences**
- 🚀 **No waiting for CI runners**
- 📱 **Easy device testing and simulator access**

**Cons:**
- 🖥️ **Requires macOS and Xcode installed**
- 👤 **Results vary by developer environment**
- 🔐 **Manual code signing setup if needed**

### ☁️ GitHub Actions Automated Builds (For Releases & CI)
**Best for:** Release builds, consistent testing, distribution, team collaboration

**Pros:**
- ✅ **Consistent, reproducible builds**
- 🔄 **Automatic environment detection** (Xcode version, macOS runner, Swift version)
- 📦 **Built-in universal binary support** (Intel + Apple Silicon)
- 🔐 **Optional code signing and notarization**
- 🌍 **Accessible to all team members**
- 📊 **Build history and logs**
- 📱 **DMG creation with configurable retention**

**Cons:**
- ⏱️ **Slower feedback cycle** (queue + build time)
- 💰 **Uses GitHub Actions minutes**
- 🚫 **Limited debugging capabilities**
- ☁️ **Requires internet connection**

## GitHub Codespaces Development

### Setting Up GitHub Codespaces

#### 1. Launch Codespace
```bash
# Option 1: From GitHub web interface
# 1. Go to github.com/milanvarady/Applite
# 2. Click "Code" → "Codespaces" → "Create codespace on main"

# Option 2: From command line (with GitHub CLI)
gh codespace create --repo milanvarady/Applite

# Option 3: Direct URL
# https://github.com/milanvarady/Applite/codespaces
```

#### 2. Codespace Environment
Your Codespace automatically includes:
- **VS Code** with Swift and Xcode extensions
- **GitHub CLI** for repository management
- **Git** configuration linked to your GitHub account
- **Terminal access** for command-line operations
- **File browser** with full repository access

#### 3. Codespace Development Workflow

**For Code Changes:**
```bash
# 1. Make your changes in VS Code
# 2. Test syntax and logic
# 3. Commit changes
git add .
git commit -m "Your change description"
git push

# 4. Use GitHub Actions for building and testing
# Go to Actions tab → Build and Release Applite → Run workflow
```

**For Build Script Development:**
```bash
# Edit workflow files directly
code .github/workflows/build-and-release.yml

# Test workflow changes by pushing and running actions
git add .github/workflows/
git commit -m "Update build workflow"
git push

# Monitor results in Actions tab
```

### Codespaces + GitHub Actions Workflow

#### Daily Development Pattern
1. **☁️ Code in Codespaces**
   - Edit source files, fix bugs, add features
   - Update documentation and configuration
   - Commit and push changes

2. **🔨 Build with GitHub Actions**
   - Trigger Debug builds for testing
   - Download artifacts to test functionality
   - Iterate based on results

3. **📱 Test with Remote macOS Device** (Optional)
   - Connect Codespace to your Mac via SSH/VPN
   - Copy built apps to your Mac for device testing
   - Use remote debugging tools

#### Remote macOS Integration

**Connecting to Your Mac from Codespaces:**
```bash
# Enable SSH on your Mac (System Preferences → Sharing → Remote Login)
# Connect from Codespace terminal
ssh your-username@your-mac-ip

# Copy build artifacts from GitHub Actions
wget https://github.com/milanvarady/Applite/actions/runs/xxx/artifacts/xxx

# Or build locally on your Mac from Codespace changes
git pull origin main
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Debug
```

**Remote Development Setup:**
```bash
# In your Codespace - set up remote development
# Install Remote-SSH extension in VS Code
# Configure SSH connection to your Mac
# Edit files in Codespace, build/test on Mac
```

### Codespaces for Different Contribution Types

#### 🐛 Bug Fixes
```bash
# 1. Launch Codespace
# 2. Reproduce issue by reading code
# 3. Fix the bug
# 4. Test with GitHub Actions Debug build
# 5. Submit pull request
```

#### 📖 Documentation Updates
```bash
# 1. Edit documentation files in Codespace
# 2. Preview markdown changes
# 3. Commit and push
# No building required!
```

#### 🔧 Build System Changes
```bash
# 1. Edit .github/workflows/ files
# 2. Test with sample workflow runs
# 3. Monitor Actions tab for results
# 4. Iterate and improve
```

#### ✨ Feature Development
```bash
# 1. Develop feature in Codespace
# 2. Use GitHub Actions for testing builds
# 3. Connect to Mac for UI/UX testing
# 4. Iterate until complete
```

### Codespaces Tips and Tricks

#### Performance Optimization
```bash
# Use larger Codespace machine for faster development
# 2-core, 4-core, or 8-core options available

# Preload dependencies
# Codespaces automatically configures Swift environment
```

#### Persistent Settings
```bash
# Your VS Code settings sync automatically
# Extensions and configurations persist
# Git credentials are automatically configured
```

#### Cost Management
```bash
# Codespaces has generous free tier (60 hours/month for 2-core)
# Stop Codespace when not in use
# Use "Suspend" for quick breaks
# Use "Stop" for longer breaks
```

### Debugging in Codespaces

#### Log Analysis
```bash
# View GitHub Actions logs
gh run list --repo milanvarady/Applite
gh run view <run-id> --log

# Download and analyze build artifacts
gh run download <run-id>
```

#### Build Script Testing
```bash
# Test build commands locally in Codespace
# (Won't actually build macOS app, but validates syntax)
xcodebuild -list -project Applite.xcodeproj
xcodebuild -showBuildSettings -project Applite.xcodeproj -scheme Applite
```

#### Remote Debugging Setup
```bash
# Forward ports for remote debugging
# Connect to Mac development environment
# Use VS Code remote development features
```

## Quick Start - Local Development

> **💡 Don't have a Mac?** Use [GitHub Codespaces](#github-codespaces-development) for cross-platform development with cloud builds.

### Prerequisites
- macOS 13.0+ (matching project deployment target)
- Xcode 14.0+ (project compatible version, latest stable recommended)
- Git

### 1. Clone and Open
```bash
git clone https://github.com/milanvarady/Applite.git
cd Applite
open Applite.xcodeproj
```

### 2. Build and Run
1. Select **Applite** scheme in Xcode
2. Choose your target (Mac, My Mac, etc.)
3. Press **⌘R** to build and run
4. Press **⌘B** to build only

### 3. Make Changes
1. Edit source files in Xcode
2. Test locally with **⌘R**
3. Commit changes with descriptive messages
4. Push to your fork and create a pull request

> **🌥️ Alternative**: Use [GitHub Codespaces](#github-codespaces-development) + [GitHub Actions](#github-actions-automated-builds) for a completely cloud-based workflow.

## GitHub Actions Automated Builds

### When to Use Automated Builds

✅ **Use GitHub Actions for:**
- 🎯 **Release builds** - Final builds for distribution
- 🧪 **Testing pull requests** - Verify changes work across environments  
- � **Creating installers** - DMG files for end users
- 🔐 **Signed/notarized builds** - App Store or direct distribution
- 👥 **Team collaboration** - Consistent builds for all contributors
- 🔄 **Integration testing** - Validate changes don't break builds

❌ **Don't use GitHub Actions for:**
- 🐛 **Active debugging** - Too slow for iterative development
- 🔬 **Exploratory coding** - Use local Xcode instead
- 📝 **Documentation changes** - Usually don't need building
- ⚡ **Quick fixes** - Test locally first

### Using the Automated Build System

#### Development Builds (Unsigned)
1. Go to **Actions** tab in GitHub
2. Select **Build and Release**
3. Click **Run workflow**
4. Configuration:
   - **Build configuration**: **Debug** (default, best for testing)
   - **Enable code signing**: ❌ **Unchecked** (faster, no signing needed)
5. Click **Run workflow**
6. Download artifacts when complete

> **⚠️ Important**: Unsigned builds require [Gatekeeper bypass](#running-unsigned-apps-gatekeeper) to run on macOS

#### Release Builds (Signed)
1. Ensure code signing is set up (see [Code Signing Setup](#code-signing-setup))
2. Go to **Actions** tab → **Build and Release**
3. Click **Run workflow**
4. Configuration:
   - **Build configuration**: **Release** (optimized for distribution)
   - **Enable code signing**: ✅ **Checked** (required for distribution)
5. Monitor build progress
6. Download signed and notarized artifacts

### 🔍 Automatic Detection Features

The build system automatically detects project settings for maximum compatibility:

**Xcode Version (Enhanced Detection):**
- **Primary**: Reads `compatibilityVersion` from `Applite.xcodeproj/project.pbxproj`
- **Fallback**: Uses `LastUpgradeCheck` if compatibilityVersion unavailable
- **Smart Mapping**: Maps project versions to available GitHub Actions versions
- **Future-proof**: Automatically supports new Xcode versions as they're released

**macOS Runner (Dynamic Selection):**
- Uses fixed `macos-15` runner for consistent, modern environment
- Ensures compatibility with latest Xcode versions and universal binary builds

**Universal Binary Support:**
- **Automatic**: All builds include both Intel (x86_64) and Apple Silicon (arm64) architectures
- **Compatible**: Works on all modern Mac computers
- **Optimized**: Single binary with native performance on both platforms

**Code Signing Detection:**
- **Project-aware**: Detects existing code signing configuration from Xcode project
- **Flexible**: Supports both workflow-level and project-level signing settings
- **Smart fallback**: Disables signing cleanly when not configured

**Build Configuration:**
- **Scheme Detection**: Automatically finds main app scheme from project
- **Bundle ID**: Extracts from project settings for accurate builds
- **Swift Version**: Detects project Swift version requirements
- **macOS Target**: Reads deployment target for compatibility

**Example Detection Results:**
```
Project Analysis Results:
• Scheme: Applite (auto-detected)
• Bundle ID: dev.aerolite.Applite
• Swift Version: 6.0
• macOS Target: 13.1
• Xcode Compatibility: 14.0 → Uses Xcode 14.x on macos-15
• Architecture: Universal (Intel + Apple Silicon)
• Code Signing: Auto-detected from project or workflow settings
```

This ensures your builds always use the appropriate environment without manual configuration.

## Local Manual Builds

> **🌥️ Using GitHub Codespaces?** You can run these commands in Codespace terminal for syntax validation and testing build scripts, but actual macOS app building requires GitHub Actions or a connected Mac device.

### Standard Development Workflow

#### 1. Daily Development
```bash
# Open project
open Applite.xcodeproj

# In Xcode:
# 1. Select "Applite" scheme
# 2. Choose "My Mac" as destination  
# 3. Build and run with ⌘R
```

#### 2. Testing Specific Configurations
```bash
# Debug build (with symbols, slower, good for debugging)
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Debug

# Release build (optimized, faster, for testing performance)
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Release
```

#### 3. Building from Command Line
```bash
# Clean build directory
xcodebuild clean -project Applite.xcodeproj -scheme Applite

# Build debug version
xcodebuild build -project Applite.xcodeproj -scheme Applite -configuration Debug

# Build release version  
xcodebuild build -project Applite.xcodeproj -scheme Applite -configuration Release

# Build and create archive
xcodebuild archive -project Applite.xcodeproj -scheme Applite -archivePath ./build/Applite.xcarchive
```

#### 4. Finding Your Built App
Built applications are located at:
```bash
# Default build location (when using Xcode)
~/Library/Developer/Xcode/DerivedData/Applite-*/Build/Products/Debug/Applite.app
~/Library/Developer/Xcode/DerivedData/Applite-*/Build/Products/Release/Applite.app

# When using xcodebuild with custom paths
./build/Debug/Applite.app
./build/Release/Applite.app
```

### Advanced Manual Builds

#### Creating DMG Installers Locally
```bash
# 1. Build the app first
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Release

# 2. Create DMG (requires create-dmg tool)
# Install create-dmg if not already installed:
brew install create-dmg

# Create the DMG
create-dmg \
  --volname "Applite Installer" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Applite.app" 200 190 \
  --hide-extension "Applite.app" \
  --app-drop-link 600 185 \
  "Applite.dmg" \
  "./build/Release/"
```

#### Code Signing Locally (Optional)
```bash
# Check available signing identities
security find-identity -v -p codesigning

# Sign the app (replace with your Developer ID)
codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name" \
  ./build/Release/Applite.app

# Verify signature
codesign --verify --deep --verbose=2 ./build/Release/Applite.app

# Check what's signed
codesign -dv --verbose=4 ./build/Release/Applite.app
```

#### Performance Testing
```bash
# Build optimized release version
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Release -arch arm64

# Profile with Instruments (GUI)
open -a "Instruments" ./build/Release/Applite.app

# Command line profiling
xcrun xctrace record --template "Time Profiler" --output trace.trace --launch -- ./build/Release/Applite.app
```

### Development Tips

#### Xcode Shortcuts for Contributors
- **⌘B** - Build only
- **⌘R** - Build and run
- **⌘U** - Run tests
- **⌘⇧K** - Clean build folder
- **⌘⇧B** - Analyze (static analysis)
- **⌘I** - Profile with Instruments

#### Debugging in Xcode
1. Set breakpoints by clicking line numbers
2. Use **po** command in debugger console to print objects
3. View memory graph with Debug Navigator
4. Use **Debug** → **View Debugging** for UI issues

#### Working with Dependencies
```bash
# If the project uses Swift Package Manager
# Dependencies are automatically resolved by Xcode

# Force dependency resolution
xcodebuild -resolvePackageDependencies

# Clean and rebuild dependencies
rm -rf ~/Library/Developer/Xcode/DerivedData/Applite-*
```

### Build Outputs

#### Local Build Artifacts
```
~/Library/Developer/Xcode/DerivedData/Applite-*/
├── Build/Products/Debug/Applite.app           # Debug build
├── Build/Products/Release/Applite.app         # Release build  
├── Logs/Build/                                # Build logs
└── Index/                                     # Code indexing data
```

#### GitHub Actions Artifacts
```
Applite-Debug/                                 # Debug build artifact
├── Applite-Debug.dmg                          # Debug DMG installer
└── BUILD_INFO.txt                             # Build metadata

Applite/                                       # Release build artifact  
├── Applite-Release.dmg                        # Release DMG installer (signed & notarized)
└── BUILD_INFO.txt                             # Build metadata
```

**Artifact Retention:**
- **Debug builds**: 7 days (for development testing)
- **Release builds**: 14 days (for distribution)

## Running Unsigned Apps (Gatekeeper)

### Why This Matters

When you build Applite without code signing (Debug builds, development builds, or local builds), macOS Gatekeeper will prevent the app from running by default. This is a security feature that protects users from running potentially harmful software.

**You'll see one of these messages:**
- *"Applite.app" cannot be opened because the developer cannot be verified.*
- *"Applite.app" is damaged and can't be opened. You should move it to the Trash.*
- *"Applite.app" cannot be opened because it is from an unidentified developer.*

### Method 1: Allow Specific App (Recommended)

This is the safest method as it only affects the specific Applite.app you want to run:

#### Step 1: Try to Open the App
1. Double-click `Applite.app` or `Applite.dmg`
2. You'll see a security warning dialog
3. Click **Cancel** (don't move to Trash)

#### Step 2: Override in System Settings
1. Open **System Settings** (or **System Preferences** on older macOS)
2. Go to **Privacy & Security**
3. Scroll down to the **Security** section
4. You'll see a message like: *"Applite.app" was blocked from use because it is not from an identified developer*
5. Click **Open Anyway** button next to this message
6. Enter your administrator password when prompted
7. Click **Open** in the confirmation dialog

#### Alternative: Right-Click Method
1. Right-click (or Control+click) on `Applite.app`
2. Select **Open** from the context menu
3. You'll see a dialog with an **Open** button
4. Click **Open** to bypass Gatekeeper for this specific app

### Method 2: Temporary Gatekeeper Disable (Advanced Users)

> **⚠️ Security Warning**: This disables Gatekeeper system-wide and makes your Mac less secure. Only use temporarily and re-enable when done.

#### Disable Gatekeeper
```bash
# Disable Gatekeeper (requires admin password)
sudo spctl --master-disable

# Verify it's disabled
spctl --status
# Should show: "assessments disabled"
```

#### Re-enable Gatekeeper (Important!)
```bash
# Re-enable Gatekeeper for security
sudo spctl --master-enable

# Verify it's enabled
spctl --status
# Should show: "assessments enabled"
```

### Method 3: Developer Workflow

For developers working on Applite regularly:

#### Option A: Remove Quarantine Attribute
```bash
# Remove quarantine attribute from the app
sudo xattr -rd com.apple.quarantine /path/to/Applite.app

# For DMG files
sudo xattr -rd com.apple.quarantine /path/to/Applite.dmg
```

#### Option B: Allow Apps from Anywhere (macOS Settings)
1. Open **System Settings** → **Privacy & Security**
2. Under **Allow apps downloaded from:**
3. Select **App Store and identified developers**
4. If you see **Anywhere** option, you can select it (may require Terminal command first)

#### Enable "Anywhere" Option (if hidden)
```bash
# Enable the "Anywhere" option in System Preferences
sudo spctl --master-disable

# This will add "Anywhere" to System Settings
# You can then go to System Settings and re-enable with "Anywhere" selected
```

### Why Code Signing Matters

**For End Users:**
- **Signed apps** run without warnings
- **Notarized apps** are additionally verified by Apple
- **App Store apps** have the highest trust level

**For Developers:**
- Unsigned builds are fine for development
- Release builds should always be signed
- Distribution requires signing + notarization

### Best Practices

1. **Development**: Use unsigned builds + Method 1 (safest)
2. **Testing**: Use Method 1 for each new build version
3. **Distribution**: Always use signed + notarized builds
4. **Never**: Leave Gatekeeper completely disabled

> **💡 Tip**: If you frequently test development builds, create a dedicated "Testing" folder and use the quarantine removal method on that folder.

## Code Signing Setup

### Prerequisites

#### Required
- **Apple Developer Program membership** ($99/year)
  - Sign up at: https://developer.apple.com/programs/
  - This is **mandatory** for code signing and notarization

#### Recommended
- macOS computer for initial certificate setup
- Admin access to your GitHub repository
- Basic understanding of command line tools

### Step 1: Apple Developer Account Setup

#### 1.1 Join Apple Developer Program
1. Visit https://developer.apple.com/programs/
2. Sign in with your Apple ID
3. Enroll in the Apple Developer Program
4. Pay the annual fee ($99 USD)
5. Wait for approval (usually 24-48 hours)

#### 1.2 Gather Required Information
Once approved, you'll need:
- **Apple ID**: The email address associated with your developer account
- **Team ID**: Found in your developer account under "Membership" section
  - Format: `1234567890` (10 characters)
  - Also visible at: https://developer.apple.com/account/#!/membership/

### Step 2: GitHub Secrets Configuration

The GitHub Actions workflow requires these secrets to be configured in your repository:

#### Required Secrets
Go to **Settings** → **Secrets and variables** → **Actions** in your GitHub repository and add:

1. **`BUILD_CERTIFICATE_BASE64`**
   - Your Developer ID Application certificate in base64 format
   - See [Certificate Setup](#step-3-create-certificates) below

2. **`P12_PASSWORD`**
   - Password for your .p12 certificate file

3. **`APPSTORE_ISSUER_ID`**
   - Your App Store Connect Issuer ID
   - Found in App Store Connect → Users and Access → Keys

4. **`APPSTORE_KEY_ID`**
   - Your App Store Connect Key ID
   - Found in App Store Connect → Users and Access → Keys

5. **`APPSTORE_PRIVATE_KEY`**
   - Your App Store Connect private key content (.p8 file)
   - The actual key content, not the file path

### Step 3: Create Certificates

#### 3.1 Generate Certificate Signing Request (CSR)

On a macOS computer:

1. Open **Keychain Access** (Applications > Utilities > Keychain Access)
2. In the menu: **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority**
3. Fill in the form:
   - **User Email Address**: Your Apple ID email
   - **Request is**: Select "Saved to disk"
4. Click **Continue** and save the `.certSigningRequest` file

#### 3.2 Create Developer ID Application Certificate

1. Visit https://developer.apple.com/account/resources/certificates
2. Click the **+** button to create a new certificate
3. Select **Developer ID Application** (for distribution outside App Store)
4. Click **Continue**
5. Upload your `.certSigningRequest` file
6. Click **Continue** and **Download** the certificate
7. Double-click the downloaded certificate to install it in Keychain Access

#### 3.3 Export Certificate for GitHub Actions

1. Open **Keychain Access**
2. Find your "Developer ID Application" certificate
3. Right-click → **Export**
4. Choose **.p12** format
5. Set a strong password (this becomes `P12_PASSWORD`)
6. Save the .p12 file

#### 3.4 Convert to Base64

```bash
# Convert .p12 to base64 for GitHub secret
base64 -i /path/to/your/certificate.p12 | pbcopy
# This copies the base64 string to clipboard
# Paste this as BUILD_CERTIFICATE_BASE64 secret
```

### Step 4: App Store Connect API Key

#### 4.1 Create API Key
1. Visit https://appstoreconnect.apple.com/access/api
2. Click **+** to create a new key
3. Enter a name (e.g., "GitHub Actions Notarization")
4. Select **Developer** role
5. Click **Generate**
6. **Download the .p8 file immediately** (you can't download it again)

#### 4.2 Get Required Values
1. **Issuer ID**: Copy from the top of the API Keys page
2. **Key ID**: Copy from the key you just created
3. **Private Key**: Open the .p8 file in a text editor and copy the entire content

### Step 5: Verify Setup

#### 5.1 Test Unsigned Build First
1. Run GitHub Actions workflow with **Enable code signing** = `false`
2. Verify the build completes successfully
3. Download and test the unsigned app (see [Gatekeeper section](#running-unsigned-apps-gatekeeper))

#### 5.2 Test Signed Build
1. Ensure all secrets are configured
2. Run GitHub Actions workflow with **Enable code signing** = `true`
3. Monitor the build logs for any signing errors
4. Download and verify the signed DMG runs without Gatekeeper warnings

### Troubleshooting Code Signing

#### Common Issues

**"No signing certificate found"**
- Verify `BUILD_CERTIFICATE_BASE64` is correctly encoded
- Check that certificate is installed in GitHub Actions runner
- Ensure certificate is not expired

**"No profiles for bundle identifier"**
- This is normal for Developer ID distribution
- The workflow handles this automatically

**"Notarization failed"**
- Verify all App Store Connect secrets are correct
- Check that the API key has Developer role
- Ensure the key hasn't been revoked

#### Debug Steps

1. **Check secret configuration**:
   ```bash
   # In workflow, secrets should show as "Set" not "Not Set"
   # Check the build environment output
   ```

2. **Verify certificate locally**:
   ```bash
   # Check available certificates
   security find-identity -v -p codesigning
   ```

3. **Test notarization manually**:
   ```bash
   # Test with your local setup
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id "your-apple-id" \
     --team-id "your-team-id" \
     --password "app-specific-password"
   ```
```

## Troubleshooting

### Step 6: Run Signed Builds

1. Go to **Actions** → **Build and Release Applite**
2. Click **Run workflow**
3. Choose your options:
   - **Configuration**: Release (recommended for distribution)
   - **Sign the release**: ✅ **Check this box**
   - **Create DMG installer**: ✅ Checked
4. Click **Run workflow**
5. Monitor the build process

The workflow will:
1. 🔍 Detect Xcode and macOS versions
2. 🔐 Install certificates
3. 🔨 Build the application
4. 📤 Export signed app
5. 🍎 Submit for notarization
6. 📦 Create signed DMG
7. ⬆️ Upload artifacts

## Troubleshooting

### Common Issues

#### Swift Package Dependencies
**Error**: "Dependencies could not be resolved because 'ifrit' contains incompatible tools version (5.9.0)"
- This occurs when Swift Package dependencies have different tools version requirements
- **Solution 1**: The workflow automatically handles this with package resolution retry logic
- **Solution 2**: In Xcode: File → Packages → Reset Package Dependencies, then Update to Latest Package Versions
- **Solution 3**: Clean Build Folder (Product → Clean Build Folder)
- **Root Cause**: Some packages declare older Swift tools versions but are compatible with newer Swift versions

**Error**: "Swift version: 'Not specified'"
- The workflow will automatically detect Swift version from project settings
- If not detected, it falls back to project defaults
- This doesn't affect the build process

#### Build Issues
**Error**: "No Xcode version detected"
- Check that your `.xcodeproj` file is in the repository root
- Verify the project file isn't corrupted
- Ensure `compatibilityVersion` is set in project.pbxproj

**Error**: "No macOS runner version detected"
- Verify `MACOSX_DEPLOYMENT_TARGET` is set in your project
- Check that the deployment target is supported (13.0+)

#### GitHub Codespaces Issues
**Error**: "Cannot build macOS app in Codespace"
- This is expected - use GitHub Actions for building
- Codespaces is for code editing and build script development
- Connect to remote Mac if you need local builds

**Issue**: "Slow Codespace performance"
- Use a larger machine type (4-core or 8-core)
- Stop unused Codespaces to free up quota
- Check your internet connection

**Issue**: "VS Code extensions not working"
- Extensions auto-install but may take time
- Manually install Swift/Xcode extensions if needed
- Reload window if extensions don't activate

#### Certificate Issues
**Error**: "No signing identity found"
- Verify the Base64 certificate is correct
- Check that the certificate password is accurate
- Ensure the certificate is a "Developer ID Application" type

#### Notarization Failures
**Error**: "Invalid credentials"
- Verify your Apple ID and Team ID
- Regenerate the app-specific password
- Check that your Apple Developer account is active

**Error**: "Notarization timeout"
- Apple's notarization service can be slow during peak times
- The workflow waits for completion automatically
- Check your Apple Developer account status

### Debug Steps

1. **Check workflow logs** for specific error messages
2. **Verify secrets** are set correctly (names are case-sensitive)
3. **Test credentials** manually using the commands in Step 4.2
4. **Contact Apple Developer Support** for account-related issues

### Re-run Failed Builds

If a build fails:
1. Fix the issue (update secrets, renew certificates, etc.)
2. Go to Actions tab
3. Find the failed workflow run
4. Click **Re-run jobs**

## Advanced Configuration

### Custom Retention Policies
Edit the workflow file to change artifact retention:
```yaml
retention-days: 30  # Change to desired number of days
```

### Custom Artifact Naming
The workflow uses this naming pattern:
```
Applite-Build-{version}-{run_number}-{configuration}-{signed|unsigned}
```

### Environment Variables
The workflow sets these environment variables:
- `XCODE_PROJECT`: Name of your Xcode project
- `SCHEME`: Build scheme name
- `PRODUCT_NAME`: Application name

### Workflow Architecture

#### Three-Job Design
1. **detect-versions**: Analyzes project and determines versions
2. **detect-runner**: Determines appropriate macOS runner
3. **build**: Performs the actual build with detected settings

#### Conditional Logic
- **Certificate installation**: Only runs when signing is enabled
- **Notarization**: Only runs when signing is enabled
- **DMG creation**: Only runs when DMG option is enabled
- **Cleanup**: Always runs, regardless of success/failure

#### Error Handling
- **Secret validation**: Checks required secrets before attempting to use them
- **Helpful error messages**: Clear guidance for resolution
- **Graceful failures**: Cleans up resources even when builds fail

## Security Best Practices

### Certificate Management
- **Rotate certificates** before they expire (valid for 3 years)
- **Use separate certificates** for different projects if needed
- **Store certificates securely** outside of version control

### Secret Management
- **Never commit secrets** to your repository
- **Use repository secrets** instead of environment secrets when possible
- **Regularly rotate** app-specific passwords
- **Limit repository access** to trusted collaborators

### Access Control
- **Enable branch protection** on main branches
- **Require pull request reviews** for workflow changes
- **Use environment protection rules** for production workflows

## Migration Notes

If you were using previous separate workflows:
- `ci.yml` - Functionality replaced by Debug builds
- `build-and-release.yml` - Merged into new unified workflow
- `build-and-release-signed.yml` - Merged into new unified workflow

The new workflow provides all previous functionality with better organization and control.

## Support and Resources

### Documentation
- [Apple Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Apple Notarization Process](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

### Getting Help
1. **Check workflow logs** for specific error messages
2. **Review this documentation** for common solutions
3. **Verify secrets** are named exactly as specified
4. **Test locally** using the same Xcode version

### Useful Commands
```bash
# List available signing identities
security find-identity -v -p codesigning

# Check certificate expiration
security find-certificate -c "Developer ID Application" -p | openssl x509 -text

# Verify app signature
codesign -dv --verbose=4 /path/to/Applite.app

# Check notarization status
xcrun stapler validate /path/to/Applite.app
```

---

## Summary

This guide covers three main development approaches for Applite:

### 🌥️ GitHub Codespaces Workflow (Cross-Platform)
1. **Launch** Codespace from GitHub repository
2. **Develop** in VS Code with full Swift support
3. **Build** using GitHub Actions (Debug/Release)
4. **Test** by downloading artifacts or connecting to Mac
5. **Collaborate** with seamless Git integration

### 🏠 Local Development Workflow (Mac Users)
1. **Clone** repository and open in Xcode
2. **Develop** locally with instant feedback (⌘R to build and run)
3. **Test** changes with immediate iteration
4. **Commit** and push to your fork
5. **Use GitHub Actions** for final testing and release builds

### ☁️ GitHub Actions Workflow (All Users)
1. **Make changes** (locally or in Codespaces)
2. **Push** to repository
3. **Trigger** automated builds via Actions tab
4. **Download** build artifacts for testing
5. **Deploy** signed/notarized builds for distribution

### Build Options Summary
- **🌥️ Codespaces + Actions**: Cross-platform development with cloud builds
- **🏠 Local Xcode**: Fast iteration with immediate feedback
- **☁️ GitHub Actions Debug**: Consistent environment testing  
- **☁️ GitHub Actions Release**: Distribution-ready builds with signing

### Auto-Detection Features
- **Xcode Version**: From project `compatibilityVersion` (currently 14.0)
- **macOS Runner**: From `MACOSX_DEPLOYMENT_TARGET` (currently 13.0 → macos-13)
- **Dynamic**: Automatically adapts to project changes

### Quick Reference Commands
```bash
# Codespaces development
gh codespace create --repo milanvarady/Applite

# Local development
git clone https://github.com/milanvarady/Applite.git
open Applite.xcodeproj

# Command line builds
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Debug
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Release
```

## Quick Reference

### Development Workflow Cheat Sheet

**📝 Making Changes**
```bash
# Codespaces (recommended for non-Mac users)
1. Create Codespace from main branch
2. Edit code in VS Code
3. Commit and push changes
4. Use GitHub Actions to build and test

# Local macOS (recommended for Mac users)  
1. git clone https://github.com/milanvarady/Applite.git
2. open Applite.xcodeproj
3. Build and run with ⌘R
4. Test changes locally before pushing
```

**🔨 Building Applite**
```bash
# Unsigned builds (for development)
GitHub Actions → Build and Release → Enable code signing: NO

# Signed builds (for distribution)  
GitHub Actions → Build and Release → Enable code signing: YES
```

**🔓 Running Unsigned Apps**
```bash
# Quick method: Right-click → Open → Open
# System Settings method: Privacy & Security → Open Anyway
# Remove quarantine: sudo xattr -rd com.apple.quarantine Applite.app
```

**📋 Required GitHub Secrets (for signing)**
- `BUILD_CERTIFICATE_BASE64` - Your .p12 certificate in base64
- `P12_PASSWORD` - Certificate password
- `APPSTORE_ISSUER_ID` - App Store Connect Issuer ID
- `APPSTORE_KEY_ID` - App Store Connect Key ID  
- `APPSTORE_PRIVATE_KEY` - App Store Connect private key content

### Common Commands

**Local Development:**
```bash
# Open project
open Applite.xcodeproj

# Command line build
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Debug

# GitHub Actions
# Go to Actions tab → Build and Release → Run workflow
```

### Getting Help
- 📖 **Build issues**: Check [Troubleshooting](#troubleshooting) section
- 🔐 **Code signing**: See [Code Signing Setup](#code-signing-setup)  
- 🌥️ **Codespaces**: GitHub Codespaces documentation
- 🐛 **Bugs**: Create issue in repository
- 💬 **Questions**: Discussions tab or community channels

> **Next Steps**: Choose your development environment and start building! For first-time contributors, we recommend starting with GitHub Codespaces to get familiar with the codebase.

---

**Contributing Guide Version**: v4.0  
**Default Configuration**: Debug (optimized for development)  
**Auto-Detection**: Xcode version from project, macos-15 runner  
**Universal Binaries**: Intel + Apple Silicon support built-in  
**Last Updated**: July 2025
