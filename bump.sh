#!/bin/bash
set -u

version=$1

exec fastlane run increment_version_number_in_xcodeproj version_number:$version
