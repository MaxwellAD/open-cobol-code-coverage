#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MaxwellAD

# This script is used to package releases of Open COBOL Unit Test
# ./package.sh <release version>
# Creates, inside package/:
# open-cobol-code-coverage-<release version>.tar.gz
# open-cobol-code-coverage-<release version>.tar.gz.sha256
set -e

if [ -z "${1}" ]; then
    echo "Usage: ./package.sh <release version>" >&2
    exit 1
fi

version=${1}

# What gets included
files_to_package="README.md code-coverage-precompiler.sh"

# Package directory
package_dir="package"

# The name of the package including version number
package_name="open-cobol-code-coverage-${version}"
tar_file="${package_name}.tar.gz"

# Stage under a versioned top-level directory so the tarball extracts into
# open-cobol-code-coverage-<version>/ rather than into the user's current directory
staging_dir="${package_dir}/${package_name}"
rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"
cp -R ${files_to_package} "${staging_dir}"

tar -czf "${package_dir}/${tar_file}" -C "${package_dir}" "${package_name}"
rm -rf "${staging_dir}"
echo "Packaged ${package_name}"

cd "${package_dir}"

# Listing decompresses the whole archive, so gzip's CRC and the tar headers
# are checked as well as showing exactly what shipped
echo "Contents:"
tar -tzf "${tar_file}" | sed 's/^/    /'

# Published alongside the tarball so downloaders can run sha256sum -c
sha256sum "${tar_file}" > "${tar_file}.sha256"
echo "Checksum written to ${package_dir}/${tar_file}.sha256"
