#!/bin/bash
set -e
ROOT=
UBRN_BIN=
PWD=

reset_args() {
  PROJECT_DIR=my-test-library
  KEEP_ROOT_ON_EXIT=false
  BOB_VERSION=latest
  PROJECT_SLUG=my-test-library
  FORCE_NEW_DIR=false
  IOS_NAME=MyTestLibrary
  SKIP_IOS=true
  SKIP_ANDROID=true
  UBRN_CONFIG=
  APP_TSX=
}

usage() {
  echo "Usage: $0 [options] [PROJECT_DIR]"
  echo ""
  echo "Options:"
  echo "  -A, --android                      Build for Android."
  echo "  -I, --ios                          Build for iOS."
  echo "  -C, --ubrn-config                  Use a ubrn config file."
  echo "  -T, --app-tsx                      Use a App.tsx file."
  echo
  echo "  -s, --slug PROJECT_SLUG            Specify the project slug (default: my-test-library)."
  echo "  -i, --ios-name IOS_NAME            Specify the iOS project name (default: MyTestLibrary)."
  echo
  echo "  -u, --builder-bob-version VERSION  Specify the version of builder-bob to use (default: latest)."
  echo "  -k, --keep-directory-on-exit       Keep the PROJECT_DIR directory even if an error does not occur."
  echo "  -f, --force-new-directory          If PROJECT_DIR directory exist, remove it first."
  echo "  -h, --help                         Display this help message."
  echo ""
  echo "Arguments:"
  echo "  PROJECT_DIR                        Specify the root directory for the project (default: my-test-library)."
}

cleanup() {
  echo "Removing $PROJECT_DIR..."
  rm -rf "$PROJECT_DIR"
  cd "$PWD"
}

diagnostics() {
  echo "-- PROJECT_DIR = $PROJECT_DIR"
  echo "-- PROJECT_SLUG = $PROJECT_SLUG"
  echo "-- IOS_NAME = $IOS_NAME"
}

error() {
  diagnostics
  echo "❌ Error: $1"
  exit 1
}

find_git_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "Project root not found" >&2
    return 1
  }
}

derive_paths() {
  ROOT=$(find_git_project_root)
  UBRN_BIN="$ROOT/bin/cli"
  PWD=$(pwd)
}

join_paths() {
  local prefix="$1"
  local suffix="$2"
  if [[ "$suffix" = /* ]] ; then
    echo -n "$suffix"
  else
    echo -n "$prefix/$suffix"
  fi
}

parse_cli_options() {
  reset_args
  # Parse command line options
  while [ $# -gt 0 ]; do
    case "$1" in
      -u|--builder-bob-version)
        BOB_VERSION="$2"
        shift
        ;;
      -s|--slug)
        PROJECT_SLUG="$2"
        shift
        ;;
      -i|--ios-name)
        IOS_NAME="$2"
        shift
        ;;
      -C|--ubrn-config)
        UBRN_CONFIG=$(join_paths "$PWD" "$2")
        shift
        ;;
      -T|--app-tsx)
        APP_TSX=$(join_paths "$PWD" "$2")
        shift
        ;;
      -k|--keep-directory-on-exit)
        KEEP_ROOT_ON_EXIT=true
        ;;
      -f|--force-new-directory)
        FORCE_NEW_DIR=true
        ;;
      -A|--android)
        SKIP_ANDROID=false
        ;;
      -I|--ios)
        SKIP_IOS=false
        ;;
      --debug)
        set -x
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        KEEP_ROOT_ON_EXIT=true
        error "Bad argument: $1"
        ;;
      *)
        PROJECT_DIR="$1"
        ;;
    esac
    shift
  done
  # Ensure PROJECT_DIR is specified
  if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR=my-test-library
  fi
}

enter_dir() {
  local dir=$1
  pushd "$dir" >/dev/null || error "Cannot enter $dir"
}

exit_dir() {
  popd >/dev/null || error "Cannot exit directory"
}

create_library() {
  local directory
  local base
  directory=$(dirname "$PROJECT_DIR")
  base=$(basename "$PROJECT_DIR")
  if [ ! -d "$directory" ]; then
    mkdir -p "$directory" || error "Cannot create $directory"
  fi

  enter_dir "$directory"

  if [ "$FORCE_NEW_DIR" == true ] && [ -d "$base" ]; then
    rm -rf "$base" || error "Failed to remove existing directory $base"
  fi

  local example_type
  if [ "$BOB_VERSION" == "latest" ] ; then
    example_type=vanilla
  fi
  echo "-- Creating library $PROJECT_SLUG with create-react-native-library@$BOB_VERSION"
  npx "create-react-native-library@$BOB_VERSION" \
    --slug "$PROJECT_SLUG" \
    --description "An automated test" \
    --author-name "James" \
    --author-email "noop@nomail.com" \
    --author-url "https://nowhere.com/james" \
    --repo-url "https://github.com/jhugman/$PROJECT_SLUG" \
    --languages cpp \
    --type module-new \
    --example $example_type \
    "$base" > /dev/null
  exit_dir
}

install_dependencies() {
  enter_dir "$PROJECT_DIR"
  # touch yarn.lock
  yarn || error "Failed to install dependencies"
  # rm yarn.lock
  exit_dir
}

install_example_dependencies() {
  enter_dir "$PROJECT_DIR/example"
  # touch yarn.lock
  yarn || error "Failed to install example dependencies"
  # rm yarn.lock
  # rm -Rf .yarn
  exit_dir
}

check_deleted_files() {
  local extensions="$1"
  local deleted_files
  echo "-- Checking for deleted files with extensions $extensions"
  deleted_files=$(git status --porcelain | grep '^ D' || true | grep -E "\\.(${extensions// /|})$" || true )

  if [ -n "$deleted_files" ]; then
    echo "Error: The following files have been deleted:"
    echo "$deleted_files"
    error
  fi
}

check_line_unchanged() {
  local file_pattern="$1"
  local search_string="$2"
  # Find all files matching the pattern
  local files
  files=$(find . -path "$file_pattern")
  for file_path in $files; do
    # Get the current content of the line containing the search string
    current_line=$(grep -E "$search_string" "$file_path" || true)
    # Get the content of the line containing the search string from the last commit
    last_commit_line=$(git show HEAD:"$file_path" | grep -E "$search_string" || true)

    # Compare the current line with the line from the last commit
    if [ "$current_line" != "$last_commit_line" ]; then
        error "$file_path: found line with \"$search_string\" to have changed"
    fi
  done
}

check_lines() {
  echo "-- Checking for unmodified lines in generated code"
  check_line_unchanged "./cpp/*.h" "#ifndef"
  check_line_unchanged "./cpp/*.h" "^namespace"
  check_line_unchanged "./cpp/*.cpp" ".h\""
  check_line_unchanged "./cpp/*.cpp" "^namespace"
  check_line_unchanged "./src/Native*" "getEnforcing"

  check_line_unchanged "./android/CMakeLists.txt" "^project"
  check_line_unchanged "./android/CMakeLists.txt" "^add_library.*SHARED"
  check_line_unchanged "./android/build.gradle" "return rootProject"
  check_line_unchanged "./android/build.gradle" "libraryName"
  check_line_unchanged "./android/src/*/*Package.*" "package"
  check_line_unchanged "./android/src/*/*Package.*" "package"
  check_line_unchanged "./android/src/*/*Module.java" "System.loadLibrary"
  check_line_unchanged "./android/src/*/*Module*" "Spec"
  check_line_unchanged "./android/src/*/*Module*" "@ReactModule"
  check_line_unchanged "./android/src/*/*Module*" "package"
  check_line_unchanged "./android/src/*/*Module.java" "public class"
  check_line_unchanged "./android/src/*/*Module.kt" "^class "
  check_line_unchanged "./android/cpp-adapter.cpp" "#include \""
  check_line_unchanged "./android/cpp-adapter.cpp" "nativeMultiply"
  check_line_unchanged "./android/cpp-adapter.cpp" "::multiply"

  check_line_unchanged "./ios/*.h" "#import"
  check_line_unchanged "./ios/*.h" "Spec.h"
  check_line_unchanged "./ios/*.h" "<Native"
  check_line_unchanged "./ios/*.h" "<RCTBridgeModule"
  check_line_unchanged "./ios/*.mm" "#import \""
  check_line_unchanged "./ios/*.mm" "@implementation"
  check_line_unchanged "./ios/*.mm" "::multiply"
  check_line_unchanged "./*.podspec" "s.name"
}

clean_turbo_modules() {
  rm -Rf cpp/ android/src/main/java ios/ src/Native* src/generated/ src/index.ts* ./*.podspec
}

generate_turbo_module_for_diffing() {
  enter_dir "$PROJECT_DIR"
  clean_turbo_modules
  echo "-- Running ubrn checkout"
  "$UBRN_BIN" checkout --config "$UBRN_CONFIG" 2>/dev/null
  echo "-- Running ubrn generate turbo-module"
  "$UBRN_BIN" generate turbo-module --config "$UBRN_CONFIG" fake_module

  local jvm_lang
  if [ "$BOB_VERSION" == "latest" ] ; then
    jvm_lang=kt
  else
    jvm_lang=java
  fi
  check_deleted_files "$jvm_lang h mm ts podspec tsx"
  check_lines

  exit_dir
}

generate_turbo_module_for_compiling() {
  enter_dir "$PROJECT_DIR"
  echo "-- Running ubrn checkout"
  clean_turbo_modules
  "$UBRN_BIN" checkout      --config "$UBRN_CONFIG"
  cp "$UBRN_CONFIG" ./ubrn.config.yaml
  if [ -f "$APP_TSX" ] ; then
    cp "$APP_TSX" ./example/src/App.tsx
  fi
  exit_dir
}

copy_into_node_modules() {
  # Source and destination directories
  local SRC_DIR="$ROOT"
  local DEST_DIR="$PROJECT_DIR/node_modules/uniffi-bindgen-react-native"

  # Use rsync to copy contents, excluding cpp_modules and rust_modules directories
  rsync -av \
    --exclude '.git' \
    --exclude 'cpp_modules' \
    --exclude 'rust_modules' \
    --exclude 'build' \
    --exclude 'target' \
  "$SRC_DIR/" "$DEST_DIR/"
}

build_android_example() {
  enter_dir "$PROJECT_DIR"
  echo "-- Running ubrn build android"
  "$UBRN_BIN" build android --config "$UBRN_CONFIG" --and-generate --targets aarch64-linux-android
  exit_dir
  enter_dir "$PROJECT_DIR/example/android"
  ./gradlew build || error "Failed to build Android example"
  exit_dir
}

build_ios_example() {
  enter_dir "$PROJECT_DIR"
  echo "-- Running ubrn build ios"
  "$UBRN_BIN" build ios     --config "$UBRN_CONFIG" --and-generate --targets aarch64-apple-ios-sim
  exit_dir
  enter_dir "$PROJECT_DIR/example/ios"
  echo "pod 'uniffi-bindgen-react-native', :path => '../../node_modules/uniffi-bindgen-react-native'" >> Podfile
  pod install || error "Cannot run Podfile"

  # Find the UDID of the first booted device, or fall back to the first available device
  udid=$(xcrun simctl list --json devices | jq -r '.devices[][] | select(.state == "Booted") | .udid')
  if [ "$udid" == "null" ]; then
    udid=$(xcrun simctl list --json devices | jq -r '.devices[][] | select(.isAvailable == true) | .udid' | head -n 1)
    xcrun simctl boot "$udid"
  fi

  if [ "$udid" == "null" ]; then
    error "No available iOS simulator found"
  fi

  xcodebuild -workspace "${IOS_NAME}Example.xcworkspace" -scheme "${IOS_NAME}Example" -configuration Debug -destination "id=$udid" || error "Failed to build iOS example"
  exit_dir
}

main() {
  parse_cli_options "$@"
  echo "ℹ️  Starting $PROJECT_SLUG"
  create_library
  if [ "$SKIP_ANDROID" == false ] || [ "$SKIP_IOS" == false ]; then
    generate_turbo_module_for_compiling
    install_dependencies
    install_example_dependencies
    copy_into_node_modules
  else
    generate_turbo_module_for_diffing
  fi
  if [ "$SKIP_ANDROID" == false ]; then
    build_android_example
  fi
  if [ "$SKIP_IOS" == false ]; then
    build_ios_example
  fi
  if [ "$KEEP_ROOT_ON_EXIT" == false ] && [ -d "$PROJECT_DIR" ]; then
    cleanup
  fi
  echo "✅ Success!"
}

run_default() {
  run_for_builder_bob "latest"
  run_for_builder_bob "0.35.1"
}

run_for_builder_bob() {
  local builder_bob_version=$1
  echo "y" | npx "create-react-native-library@$builder_bob_version" > /dev/null 2>&1

  local fixture_dir="$ROOT/integration/fixtures/turbo-module-testing"
  local working_dir="/tmp/turbomodule-tests"
  local config="$fixture_dir/ubrn.config.yaml"
  local app_tsx="$fixture_dir/App.tsx"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug dummy-lib \
    "$working_dir/dummy-lib"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug rn-dummy-lib \
    "$working_dir/rn-dummy-lib"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug react-native-dummy-lib \
    "$working_dir/react-native-dummy-lib"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug dummy-lib-react-native \
    "$working_dir/dummy-lib-react-native"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug dummy-lib-rn \
    "$working_dir/dummy-lib-rn"
  # ReactNativeDummyLib fails with "› Must be a valid npm package name"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug @my-org/react-native-dummy-lib \
    "$working_dir/@my-org/react-native-dummy-lib"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug @my-org/dummy-lib \
    "$working_dir/@my-org/dummy-lib"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug @react-native/dummy-lib \
    "$working_dir/@react-native/dummy-lib"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug @react-native-org/dummy-lib \
    "$working_dir/@react-native-org/dummy-lib"
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --slug @react-native/dummy-lib \
    "$working_dir/@react-native/react-native-lib"

  # Build for Android
  main \
    --force-new-directory \
    --keep-directory-on-exit \
    --ubrn-config "$config" \
    --app-tsx "$app_tsx" \
    --builder-bob-version "$builder_bob_version" \
    --slug react-native-dummy-lib-for-android \
    --android \
    "$working_dir/react-native-dummy-lib-for-android"
  local os
  os=$(uname -o)
  # Build for iOS
  if [ "$os" == "Darwin" ] ; then
    main \
      --force-new-directory \
      --keep-directory-on-exit \
      --ubrn-config "$config" \
      --app-tsx "$app_tsx" \
      --builder-bob-version "$builder_bob_version" \
      --slug react-native-dummy-lib-for-ios \
      --ios \
      --ios-name DummyLibForIos \
      "$working_dir/react-native-dummy-lib-for-ios"
  fi

  if [ true ] ; then
    return
  fi
  main \
    --force-new-directory \
    --ubrn-config "$config" \
    --builder-bob-version "$builder_bob_version" \
    --android \
    --app-tsx "$app_tsx" \
    --slug @my-org/react-native-dummy-lib-for-android \
    "$working_dir/@my-org/react-native-dummy-lib-for-android"

  if [ "$os" == "Darwin" ] ; then
    main \
      --force-new-directory \
      --ubrn-config "$config" \
      --builder-bob-version "$builder_bob_version" \
      --ios \
      --app-tsx "$app_tsx" \
      --ios-name ReactNativeDummyLibForIos \
      --slug @my-org/react-native-dummy-lib-for-ios \
      "$working_dir/@my-org/react-native-dummy-lib-for-ios"
  fi
}

derive_paths
# Check if there are no command line arguments
if [ $# -eq 0 ]; then
  run_default
else
  main "$@"
fi
