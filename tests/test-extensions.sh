#!/bin/bash
#
# Copyright (C) 2011 Colin Walters <walters@verbum.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA.

set -euo pipefail

. $(dirname $0)/libtest.sh

skip_without_bwrap
skip_without_user_xattrs

echo "1..2"

make_extension () {
    local ID=$1
    local VERSION=$2

    local DIR=`mktemp -d`

    ${FLATPAK} build-init ${DIR} ${ID} ${ID} ${ID}
    sed -i s/Application/Runtime/ ${DIR}/metadata
    mkdir -p ${DIR}/usr
    touch ${DIR}/usr/exists
    touch ${DIR}/usr/extension-$ID:$VERSION

    ${FLATPAK} build-export --runtime ${GPGARGS-} repo ${DIR} ${VERSION}
    rm -rf ${DIR}

    ${FLATPAK} --user install test-repo $ID $VERSION
}

add_extensions () {
    local DIR=$1

    mkdir -p $DIR/files/foo/ext1
    mkdir -p $DIR/files/foo/ext2
    mkdir -p $DIR/files/foo/ext3
    mkdir -p $DIR/files/foo/ext4
    mkdir -p $DIR/files/foo/none
    mkdir -p $DIR/files/foo/dir
    mkdir -p $DIR/files/foo/dir/foo
    mkdir -p $DIR/files/foo/dir2
    mkdir -p $DIR/files/foo/dir2/foo

    cat >> $DIR/metadata <<EOF
[Extension org.test.Extension1]
directory=foo/ext1

[Extension org.test.Extension2]
directory=foo/ext2
version=master

[Extension org.test.Extension3]
directory=foo/ext3
version=not-master

[Extension org.test.Extension4]
directory=foo/ext4
version=not-master

[Extension org.test.None]
directory=foo/none

[Extension org.test.Dir]
directory=foo/dir
subdirectories=true

[Extension org.test.Dir2]
directory=foo/dir2
subdirectories=true

EOF
}

ostree init --repo=repo --mode=archive-z2
. $(dirname $0)/make-test-runtime.sh org.test.Platform bash ls cat echo readlink > /dev/null
. $(dirname $0)/make-test-app.sh > /dev/null

# Modify platform metadata
ostree checkout -U --repo=repo runtime/org.test.Platform/${ARCH}/master platform
add_extensions platform
ostree commit --repo=repo --owner-uid=0 --owner-gid=0 --no-xattrs --branch=runtime/org.test.Platform/${ARCH}/master -s "modified metadata" platform
ostree summary -u --repo=repo

${FLATPAK} remote-add --user --no-gpg-verify test-repo repo
${FLATPAK} --user install test-repo org.test.Platform master
${FLATPAK} --user install test-repo org.test.Hello master

make_extension org.test.Extension1 master
make_extension org.test.Extension1 not-master
make_extension org.test.Extension2 master
make_extension org.test.Extension2 not-master
make_extension org.test.Extension3 master
make_extension org.test.Extension3 not-master
make_extension org.test.Extension4 master
make_extension org.test.Dir.foo master

assert_has_extension_file () {
    local prefix=$1
    local file=$2 
    run_sh "test -f $prefix/foo/$file" || (echo 1>&2 "Couldn't find '$file'"; exit 1)
}

assert_not_has_extension_file () {
    local prefix=$1
    local file=$2 
    if run_sh "test -f $prefix/foo/$file" ; then
        echo 1>&2 "File '$file' exists";
        exit 1
    fi
}

assert_has_extension_file /usr ext1/exists
assert_has_extension_file /usr ext1/extension-org.test.Extension1:master
assert_has_extension_file /usr ext2/exists
assert_has_extension_file /usr ext2/extension-org.test.Extension2:master
assert_has_extension_file /usr ext3/exists
assert_has_extension_file /usr ext3/extension-org.test.Extension3:not-master
assert_not_has_extension_file /usr ext4/exists
assert_has_extension_file /usr dir/foo/exists
assert_has_extension_file /usr dir/foo/extension-org.test.Dir.foo:master
assert_not_has_extension_file /usr dir2/foo/exists

echo "ok runtime extensions"

# Modify app metadata
ostree checkout -U --repo=repo app/org.test.Hello/${ARCH}/master hello
add_extensions hello
ostree commit --repo=repo --owner-uid=0 --owner-gid=0 --no-xattrs --branch=app/org.test.Hello/${ARCH}/master -s "modified metadata" hello
ostree summary -u --repo=repo

${FLATPAK} --user update org.test.Hello master

assert_has_extension_file /app ext1/exists
assert_has_extension_file /app ext1/extension-org.test.Extension1:master
assert_has_extension_file /app ext2/exists
assert_has_extension_file /app ext2/extension-org.test.Extension2:master
assert_has_extension_file /app ext3/exists
assert_has_extension_file /app ext3/extension-org.test.Extension3:not-master
assert_not_has_extension_file /app ext4/exists
assert_has_extension_file /app dir/foo/exists
assert_has_extension_file /app dir/foo/extension-org.test.Dir.foo:master
assert_not_has_extension_file /app dir2/foo/exists

echo "ok app extensions"
