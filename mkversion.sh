#!/bin/sh
set -e

# debugging if anything fails is tricky as dh-golang eats up all output
# uncomment the lines below to get a useful trace if you have to touch
# this again (my advice is: DON'T)
#set -x
#logfile=/tmp/mkversions.log
#exec >> $logfile 2>&1
#echo "env: $(set)"
#echo "mkversion.sh run from: $0"
#echo "pwd: $(pwd)"

# we have two directories we need to care about:
# - our toplevel pkg builddir which is where "mkversion.sh" is located
#   and where "snap-confine" expects its cmd/VERSION file
# - the GO_GENERATE_BUILDDIR which may be the toplevel pkg dir. but
#   during "dpkg-buildpackage" it will become a different _build/ dir
#   that dh-golang creates and that only contains a subset of the
#   files of the toplevel buildir. 
PKG_BUILDDIR=$(dirname "$0")
GO_GENERATE_BUILDDIR="$(pwd)"

# run from "go generate" adjust path
if [ "$GOPACKAGE" = "cmd" ]; then
    GO_GENERATE_BUILDDIR="$(pwd)/.."
fi

OUTPUT_ONLY=false
if [ "$1" = "--output-only" ]; then
    OUTPUT_ONLY=true
    shift
fi

# If the version is passed in as an argument to mkversion.sh, let's use that.
if [ -n "$1" ]; then
    version_from_user="$1"
fi

# Let's try to derive the version from git..
if command -v git >/dev/null; then
    # not using "--dirty" here until the following bug is fixed:
    # https://bugs.launchpad.net/snapcraft/+bug/1662388
    version_from_git="$(git describe --always | sed -e 's/-/+git/;y/-/./' )"
fi

# at this point we maybe in _build/src/github etc where we have no
# debian/changelog (dh-golang only exports the sources here)
# switch to the real source dir for the changelog parsing
if command -v dpkg-parsechangelog >/dev/null; then
    version_from_changelog="$(cd "$PKG_BUILDDIR"; dpkg-parsechangelog --show-field Version)";
fi

# select version based on priority
if [ -n "$version_from_user" ]; then
    # version from user always wins
    v="$version_from_user"
    o="user"
elif [ -n "$version_from_git" ]; then
    v="$version_from_git"
    o="git"
elif [ -n "$version_from_changelog" ]; then
    v="$version_from_changelog"
    o="changelog"
else
    echo "Cannot generate version"
    exit 1
fi

# if we don't have a user provided versions and if the version is not
# a release (i.e. the git tag does not match the debian changelog
# version) then we need to construct the version similar to how we do
# it in a packaging recipe. We take the debian version from the changelog
# and append the git revno and commit hash. A simpler approach would be
# to git tag all pre/rc releases.
if [ -z "$version_from_user" ] && [ "$version_from_git" != "" ] && [ "$version_from_git" != "$version_from_changelog" ]; then
    revno=$(git describe --always --abbrev=7|cut -d- -f2)
    commit=$(git describe --always --abbrev=7|cut -d- -f3)
    v="${version_from_changelog}+git${revno}.${commit}"
    o="changelog+git"
fi


if [ "$OUTPUT_ONLY" = true ]; then
    echo "$v"
    exit 0
fi

echo "*** Setting version to '$v' from $o." >&2

cat <<EOF > "$GO_GENERATE_BUILDDIR/snapdtool/version_generated.go"
package snapdtool

// generated by mkversion.sh; do not edit

func init() {
	Version = "$v"
}
EOF

cat <<EOF > "$PKG_BUILDDIR/cmd/VERSION"
$v
EOF

cat <<EOF > "$PKG_BUILDDIR/data/info"
VERSION=$v
EOF
