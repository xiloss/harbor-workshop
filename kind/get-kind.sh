#!/bin/bash

# Fetch and display available versions
echo "Fetching available versions of kind..."
version_list=$(curl -sS https://api.github.com/repos/kubernetes-sigs/kind/releases | grep 'tag_name' | cut -d '"' -f 4)
echo "Select a version of kind to install:"

select version in $version_list; do
    if [[ -n "$version" ]]; then
        echo "You selected $version"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# Download selected version
echo "Downloading kind $version..."
curl -sSLo ./kind-${version} "https://kind.sigs.k8s.io/dl/$version/kind-$(uname)-amd64"

# Make it executable
chmod +x ./kind-${version}

# Move it to a bin directory
sudo mv ./kind-${version} /usr/local/bin/kind

# Verify installation
kind --version
