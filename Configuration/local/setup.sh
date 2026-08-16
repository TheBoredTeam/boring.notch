#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
repository_root="${script_dir:h:h}"
derived_data_path="$repository_root/.build/DerivedData"
source_packages_path="$repository_root/.build/SourcePackages"
destination="platform=macOS,arch=$(uname -m)"

build_arguments=(
    -quiet
    -project "$repository_root/boringNotch.xcodeproj"
    -scheme boringNotch
    -configuration Debug
    -destination "$destination"
    -derivedDataPath "$derived_data_path"
    -clonedSourcePackagesDirPath "$source_packages_path"
)

cd "$repository_root"

echo "Resolving Swift package dependencies..."
xcodebuild "${build_arguments[@]}" -resolvePackageDependencies

echo "Building Boring Notch..."
xcodebuild "${build_arguments[@]}" build

app_path="$derived_data_path/Build/Products/Debug/boringNotch.app"
codesign --verify --deep --strict "$app_path"

echo "Setup complete. Built app: $app_path"
