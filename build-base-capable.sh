#!/usr/bin/env bash

set -xeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

arch="x86_64"
backend="composefs"
containerfile="Containerfile.bare-metal"
name="bootc-bare-metal-deriv"
registry=""
release="44"

declare -a tag_suffixes=()

usage() {
    cat <<'EOF'
Usage: build-base-capable.sh [OPTIONS] [-- PODMAN_BUILD_ARG ...]

Build and optionally push a derivative bootc image.

Options:
  -a ARCH          x86_64 or aarch64 (default: x86_64)
  -b BACKEND       composefs or ostree (default: composefs)
  -c CONTAINERFILE Containerfile path (default: Containerfile.bare-metal)
  -d REGISTRY      Push destination, for example ghcr.io/example
  -n NAME          Image name (default: bootc-bare-metal-deriv)
  -r RELEASE       Fedora release (default: 44)
  -s TAG_SUFFIX    Tag suffix; may be repeated (default: main-BACKEND-ARCH)
  -h               Show this help

Generated tags are RELEASE-TAG_SUFFIX.
Registry authentication must be performed before running this script.
Arguments after -- are passed unchanged to podman build. These arguments are
caller-controlled and may weaken the default unprivileged security profile.
EOF
}

die() {
    echo "$1" >&2
    exit 2
}

assert_not_empty() {
    local argn="$1"
    local val="$2"

    [[ -n ${val} ]] || die "Invalid argument for -${argn}: must not be empty"
    [[ ${val} != -- ]] || die "Invalid argument for -${argn}: must not be --"
}

original_args=("$@")
while getopts ":a:b:c:d:hn:r:s:" opt; do
    case ${opt} in
        a) assert_not_empty "a" "$OPTARG"; arch="$OPTARG" ;;
        b) assert_not_empty "b" "$OPTARG"; backend="$OPTARG" ;;
        c) assert_not_empty "c" "$OPTARG"; containerfile="$OPTARG" ;;
        d) assert_not_empty "d" "$OPTARG"; registry="${OPTARG%/}" ;;
        h) usage; exit 0 ;;
        n) assert_not_empty "n" "$OPTARG"; name="$OPTARG" ;;
        r) assert_not_empty "r" "$OPTARG"; release="$OPTARG" ;;
        s) assert_not_empty "s" "$OPTARG"; tag_suffixes+=("$OPTARG") ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage >&2; exit 1 ;;
        :) die "Missing argument: -$OPTARG" ;;
    esac
done

options_terminated=false
if ((OPTIND > 1)) && [[ ${original_args[OPTIND - 2]} == -- ]]; then
    options_terminated=true
fi
shift $((OPTIND - 1))

extra_podman_args=()
if (($#)); then
    if [[ ${options_terminated} != true ]]; then
        echo "Unexpected positional argument: $1" >&2
        die "Podman build arguments must follow --"
    fi
    extra_podman_args=("$@")
fi
case ${arch} in
    x86_64) platform_arch="amd64" ;;
    aarch64) platform_arch="arm64" ;;
    *) die "Invalid argument for -a: unsupported architecture: ${arch}" ;;
esac

# Derivatives inherit their backend; neither backend composes a new rootfs.
case ${backend} in
    composefs|ostree) ;;
    *) die "Invalid argument for -b: unsupported backend: ${backend}" ;;
esac

if [[ ${containerfile} != /* ]]; then
    containerfile="${script_dir}/${containerfile}"
fi
[[ -f ${containerfile} ]] || die "Containerfile does not exist: ${containerfile}"

if ((${#tag_suffixes[@]} == 0)); then
    tag_suffixes+=("main-${backend}-${arch}")
fi

tagged_names=()
for suffix in "${tag_suffixes[@]}"; do
    tagged_names+=("${name}:${release}-${suffix}")
done
tag_opts=()
for tagged_name in "${tagged_names[@]}"; do
    tag_opts+=("-t" "${tagged_name}")
done

# Bash 3.2 treats an empty array expansion as unset under nounset.
build_opts=(--pull=always)
if ((${#extra_podman_args[@]})); then
    build_opts+=("${extra_podman_args[@]}")
fi

podman build \
    "${build_opts[@]}" \
    --platform "linux/${platform_arch}" \
    --build-arg release="${release}" \
    --build-arg backend="${backend}" \
    --build-arg arch="${arch}" \
    "${tag_opts[@]}" \
    -f "${containerfile}" \
    "${script_dir}"

if [[ -n ${registry} ]]; then
    for tagged_name in "${tagged_names[@]}"; do
        podman push "${tagged_name}" "${registry}/${tagged_name}"
    done
fi
