# Fix GoogleSignIn Package - Quick Steps

## 🚨 Error: "No such module 'GoogleSignIn'"

The GoogleSignIn Swift package needs to be added to your Xcode project.

## ✅ How to Fix (2 minutes):

### Step 1: Open Your Project
- Xcode should already be open with your Spark project

### Step 2: Add GoogleSignIn Package
1. In Xcode, go to **File** → **Add Package Dependencies...**
2. Paste this URL: `https://github.com/google/GoogleSignIn-iOS`
3. Click **Add Package**
4. Select **GoogleSignIn** and **GoogleSignInSwift** 
5. Click **Add Package**

### Step 3: Verify Installation
1. Build your project (**Cmd+B**)
2. The "No such module 'GoogleSignIn'" error should be gone

## 🔧 Alternative: Command Line Fix

If you prefer, run this in Terminal:

```bash
# Navigate to your project
cd /Users/tommykeeley/MuckStack-Projects/spark--iOS

# Clean build folder
rm -rf build/
rm -rf DerivedData/

# Open Xcode and let it resolve packages
open Spark.xcodeproj
```

Then add the package URL in Xcode as described above.

## ✅ Expected Result

After adding the package, your project should have:
- ✅ GoogleSignIn module available
- ✅ GoogleSignInSwift module available  
- ✅ No build errors
- ✅ Google Sign In button functional

The GoogleSignIn package is required for the authentication features we implemented.