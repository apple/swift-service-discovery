#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftServiceDiscovery open source project
##
## Copyright (c) 2020 Apple Inc. and the SwiftServiceDiscovery project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIO open source project
##
## Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -ex

my_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root_path="$my_path/.."
version=$(git describe --abbrev=0 --tags || echo "0.0.0")
modules=(ServiceDiscovery)

if [[ "$(uname -s)" == "Linux" ]]; then
  # build code if required
  if [[ ! -d "$root_path/.build/x86_64-unknown-linux" ]]; then
    swift build
  fi
  # setup source-kitten if required
  source_kitten_source_path="$root_path/.SourceKitten"
  if [[ ! -d "$source_kitten_source_path" ]]; then
    git clone https://github.com/jpsim/SourceKitten.git "$source_kitten_source_path"
  fi
  source_kitten_path="$source_kitten_source_path/.build/x86_64-unknown-linux/debug"
  if [[ ! -d "$source_kitten_path" ]]; then
    rm -rf "$source_kitten_source_path/.swift-version"
    cd "$source_kitten_source_path" && swift build && cd "$root_path"
  fi
  # generate
  mkdir -p "$root_path/.build/sourcekitten"
  for module in "${modules[@]}"; do
    if [[ ! -f "$root_path/.build/sourcekitten/$module.json" ]]; then
      "$source_kitten_path/sourcekitten" doc --spm-module $module > "$root_path/.build/sourcekitten/$module.json"
    fi
  done
fi

[[ -d docs/$version ]] || mkdir -p docs/$version
[[ -d swift-service-discovery.xcodeproj ]] || swift package generate-xcodeproj

# run jazzy
if ! command -v jazzy > /dev/null; then
  gem install jazzy --no-ri --no-rdoc
fi

jazzy_dir="$root_path/.build/jazzy"
rm -rf "$jazzy_dir"
mkdir -p "$jazzy_dir"

module_switcher="$jazzy_dir/README.md"
jazzy_args=(--clean
            --author 'SwiftServiceDiscovery team'
            --readme "$module_switcher"
            --author_url https://github.com/apple/swift-service-discovery
            --github_url https://github.com/apple/swift-service-discovery
            --github-file-prefix https://github.com/apple/swift-service-discovery/tree/$version
            --theme fullwidth
            --xcodebuild-arguments -scheme,swift-service-discovery-Package)
cat > "$module_switcher" <<"EOF"
# SwiftServiceDiscovery Docs

SwiftServiceDiscovery is a Swift service discovery API package.

To get started with SwiftServiceDiscovery, [`import ServiceDiscovery`](../ServiceDiscovery/index.html). The
most important type is [`ServiceDiscovery`](https://apple.github.io/swift-service-discovery/docs/current/ServiceDiscovery/Protocols/ServiceDiscovery.html)
which you can use for service discovery.
EOF

for module in "${modules[@]}"; do
  args=("${jazzy_args[@]}" --output "$jazzy_dir/docs/$version/$module" --docset-path "$jazzy_dir/docset/$version/$module"
        --module "$module" --module-version $version
        --root-url "https://apple.github.io/swift-service-discovery/docs/$version/$module/")
  if [[ -f "$root_path/.build/sourcekitten/$module.json" ]]; then
    args+=(--sourcekitten-sourcefile "$root_path/.build/sourcekitten/$module.json")
  fi
  jazzy "${args[@]}"
done

# push to github pages
if [[ $PUSH == true ]]; then
  BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
  GIT_AUTHOR=$(git --no-pager show -s --format='%an <%ae>' HEAD)
  git fetch origin +gh-pages:gh-pages
  git checkout gh-pages
  rm -rf "docs/$version"
  rm -rf "docs/current"
  cp -r "$jazzy_dir/docs/$version" docs/
  cp -r "docs/$version" docs/current
  git add --all docs
  echo '<html><head><meta http-equiv="refresh" content="0; url=docs/current/ServiceDiscovery/index.html" /></head></html>' > index.html
  git add index.html
  touch .nojekyll
  git add .nojekyll
  changes=$(git diff-index --name-only HEAD)
  if [[ -n "$changes" ]]; then
    echo -e "changes detected\n$changes"
    git commit --author="$GIT_AUTHOR" -m "publish $version docs"
    git push origin gh-pages
  else
    echo "no changes detected"
  fi
  git checkout -f $BRANCH_NAME
fi
