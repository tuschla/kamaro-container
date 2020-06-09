#!/usr/bin/bash
set -e
basedir="$(dirname "$0")"

usage_info="Usage: $0 [[-b <base_image>] [-n <image_name>] <build-dir>]

Must be either run with sudo, or as a user who is in the group 'docker'.

Builds the docker image described in <build-dir> and tags it with the given name
<image_name>. If no name is given, the name kamaro:<build_dir> is used.
If <base_image> is given, the existing image is used as the base of the build. Otherwise,
the default image described in the Dockerfile is used. Kamaro images will be (re)built,
even if they already exist.
When building $basedir/melodic without specifying a base image, the
kamaro:nvidia-melodic-base image will be used as a base image if the nvidia graphic driver
is detected.

<build_dir> defaults to $basedir/melodic
"

if [[ "$(whoami)" != 'root' ]] && ! [ "$(groups | grep -F 'docker')" ]; then
  echo 'Must be either in group "docker" or be run with sudo'
  exit 1
fi
if [[ "$(whoami)" == 'root' ]] && [ -z "$SUDO_USER" ]; then
  echo "Cannot be root! Use sudo or add user to the docker group"
  exit 1
fi

image_name=""
arg_base_image=""
while getopts hb:n: opt; do
  case $opt in
    b)
      arg_base_image="$OPTARG"
      ;;
    n)
      image_name="$OPTARG"
      ;;
    ?)
      echo "$usage_info"
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

build_dir="${1:-$basedir/melodic}"
if ! [ -d "$build_dir" ] || ! [ -f "$build_dir/Dockerfile" ]; then
  echo "$build_dir is not a docker build directory"
  exit 1
fi

if [ -z "$image_name" ]; then
  image_name="kamaro:$(basename "$build_dir")"
fi

if [ -z "$arg_base_image" ]; then
  if [[ "$(basename "$build_dir")" == "melodic" ]] && glxinfo | grep -iq "vendor.*nvidia"; then
    echo "$(tput setaf 2)Detected nvidia graphics driver$(tput sgr0)"
    base_image="kamaro:nvidia-melodic-base"
  else
    base_image="$(sed -En 's/^ARG[[:space:]]+BASE_IMAGE=([[:alnum:]:_-]+)/\1/p' "$build_dir/Dockerfile")"
    if [ -z "$base_image" ]; then
      echo "No default base image specified in $build_dir/Dockerfile"
      exit 1
    fi
  fi
  if echo "$base_image" | grep -qE '^kamaro:.+'; then
    echo "$(tput setaf 3)Building $base_image as a dependency...$(tput sgr0)"
    if ! bash "$0" "$basedir/${base_image#kamaro:}"; then
      echo "Failed to build dependency $base_image"
      exit 1
    fi
  fi
else
  # do not rebuild kamaro images when the base_image is explicitly given
  base_image="$arg_base_image"
fi

if [ "$SUDO_USER" ]; then
  _user="$SUDO_USER"
  _uid="$SUDO_UID"
  _home="/home/$SUDO_USER"
else
  _user="$USER"
  _uid="$UID"
  _home="$HOME"
fi

cd "$build_dir"
docker build \
  --build-arg BASE_IMAGE=$base_image \
  --build-arg user=$_user \
  --build-arg uid=$_uid \
  --build-arg home=$_home \
  --network=host \
  -t "$image_name" .

echo "$(tput setaf 2)Built image $image_name$(tput sgr0)"
