#!/usr/bin/env bash
set -e 

ARCH="amd64"
DIST="xenial"
BUILDAREA="/tmp/dehydrated-build"
BRANCH="debian"

if [ "$(git rev-parse --abbrev-ref HEAD)" != $BRANCH ]; then
    echo "You are not on the $BRANCH branch, aborting"
    /bin/false
fi;

export VERSION=$(date "+%Y%m%d.%H%M%S")

echo "Generating changelog changelog"
gbp dch --debian-tag="%(version)s" --new-version=$VERSION --debian-branch $BRANCH --release --commit


echo "Building package for $DIST"

git checkout $BRANCH
TEMPBRANCH="$BRANCH-build-$DIST-$VERSION"
git checkout -b $TEMPBRANCH

mkdir -p $BUILDAREA-$DIST
gbp buildpackage --git-pbuilder --git-export-dir=$BUILDAREA-$DIST --git-dist=$DIST --git-arch=$ARCH \
--git-debian-branch=$TEMPBRANCH --git-ignore-new

git checkout $BRANCH
git branch -D $TEMPBRANCH

echo
echo "*************************************************************"
echo

echo "Creating tag $VERSION"
git tag $VERSION

echo "Now push the commit with the version update and the tag: git push; git push --tags"
