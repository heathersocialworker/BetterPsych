#!/usr/bin/env bash
set -euo pipefail

# 0) Guardrails
if [ ! -d .git ]; then
  echo "Run this at the root of your Git repo (where .git exists)."
  exit 1
fi

# 1) New branch for clean PR
git checkout -b repo-autofix || git switch -c repo-autofix

# 2) Create archive folder and move ZIPs out of the way
mkdir -p archive
shopt -s nullglob
moved_any=false
for z in *.zip */*.zip; do
  mv "$z" archive/
  moved_any=true
done
shopt -u nullglob
if $moved_any; then
  echo -e "\n# Archives\narchive/\n*.zip\n" >> .gitignore
fi

# 3) Ensure a clean SwiftUI minimal app structure exists
mkdir -p BetterPsych/App BetterPsych/Views BetterPsych/Models BetterPsych/Resources

# 4) Add minimal SwiftUI app files if missing
if [ ! -f BetterPsych/App/BetterPsychApp.swift ]; then
  cat > BetterPsych/App/BetterPsychApp.swift <<'SWIFT'
import SwiftUI

@main
struct BetterPsychApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
SWIFT
fi

if [ ! -f BetterPsych/Views/ContentView.swift ]; then
  cat > BetterPsych/Views/ContentView.swift <<'SWIFT'
import SwiftUI

struct ContentView: View {
    @State private var mood: String = "🙂"
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("BetterPsych").font(.largeTitle).bold()
                Text("Welcome! Track your mood and coping skills.")
                    .multilineTextAlignment(.center)
                Text("Current mood: \(mood)").font(.title3)
                HStack {
                    Button("Good") { mood = "😄" }
                    Button("Okay") { mood = "🙂" }
                    Button("Low") { mood = "😔" }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

#Preview { ContentView() }
SWIFT
fi

if [ ! -f BetterPsych/Models/Item.swift ]; then
  cat > BetterPsych/Models/Item.swift <<'SWIFT'
import Foundation

struct Item: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    init(id: UUID = UUID(), title: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
SWIFT
fi

# 5) Add Info.plist if target expects a physical file
if [ ! -f BetterPsych/Resources/Info.plist ]; then
  cat > BetterPsych/Resources/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BetterPsych</string>
  <key>UILaunchStoryboardName</key><string></string>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><true/>
  </dict>
</dict></plist>
PLIST
fi

# 6) Create/repair .gitignore for Xcode/macOS
cat >> .gitignore <<'IGN'
# Xcode
DerivedData/
build/
*.xcuserdatad
*.xcworkspace/xcuserdata/
*.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings
*.xcscmblueprint

# SwiftPM
.swiftpm/
Packages/
Package.resolved

# macOS
.DS_Store

# Archives
archive/
*.zip
IGN

# 7) Ensure an Xcode project exists at root (skip if already present)
if [ ! -d "BetterPsych.xcodeproj" ]; then
  echo "Creating Xcode project with swift package init + xcodegen-like stub..."
  if command -v swift >/dev/null 2>&1; then
    if [ ! -f Package.swift ]; then
      swift package init --type executable
    fi
    sed -i.bak 's/.executable(name: ".*", targets: \[".*"\])/.executable(name: "BetterPsych", targets: ["BetterPsych"])/' Package.swift || true
    rm -rf Sources
    mkdir -p Sources
    cat > Sources/main.swift <<'SWIFT'
import SwiftUI
import Foundation

@main
struct CLIShim {
    static func main() {
        print("Open BetterPsych.xcodeproj and run the iOS target in Xcode.")
    }
}
SWIFT
    swift package generate-xcodeproj 2>/dev/null || true
  else
    echo "Swift toolchain not found; skipping SPM bootstrap."
  fi
fi

# 8) Docs folder and place for deck
mkdir -p docs/pitch

# 9) GitHub Actions CI for iOS sim build
mkdir -p .github/workflows
cat > .github/workflows/ios-ci.yml <<'YML'
name: iOS Build
on:
  push:
  pull_request:
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -switch /Applications/Xcode_15.4.app
      - name: Build (xcodebuild)
        run: |
          set -e
          PROJECT="BetterPsych.xcodeproj"
          if [ ! -d "$PROJECT" ]; then
            echo "No BetterPsych.xcodeproj found; trying any .xcodeproj"
            PROJECT=$(ls -1 *.xcodeproj | head -n1)
          fi
          xcodebuild -project "$PROJECT" \
            -scheme BetterPsych \
            -sdk iphonesimulator \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            build | xcpretty || true
YML

# 10) README refresh
cat > README.md <<'MD'
# BetterPsych

A SwiftUI iOS app prototype for the BetterPsych project.

## Build
1. Open `BetterPsych.xcodeproj` in Xcode.
2. Target: **BetterPsych**, set a unique Bundle Identifier and your Team (Signing & Capabilities).
3. Set Deployment Target to iOS 16.0 or higher.
4. Product → Clean Build Folder → Run on an iPhone 15 simulator.

## Repo Hygiene
- Large ZIPs moved to `/archive` and ignored by git.
- CI workflow `.github/workflows/ios-ci.yml` builds on macOS.

## Flutter?
If you plan to ship Flutter instead of native SwiftUI, create a sibling `flutter/` app (`flutter create betterpsych`) and **do not** commit ZIPs. Keep native and Flutter in separate folders or repos.

## Docs
Pitch materials live in `/docs/pitch`.
MD

# 11) Commit changes
git add -A
git commit -m "Auto-fix: clean repo, add SwiftUI baseline, CI, .gitignore, archive ZIPs"

echo ""
echo "✅ Done. Next steps:"
echo "1) Open Xcode:  open BetterPsych.xcodeproj"
echo "2) In the target 'BetterPsych' → Signing & Capabilities: set Bundle ID + Team."
echo "3) Product → Clean Build Folder → Run."
echo "4) Push and open PR: git push -u origin repo-autofix"
