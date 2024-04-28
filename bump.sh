#!/bin/bash
set -u

version=$(git cliff --bumped-version)
version=$(echo $version | sed 's/v//g')

exec fastlane run increment_version_number_in_xcodeproj version_number:$version
