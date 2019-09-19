#!/bin/bash
if [[ $# -eq 1 ]]; then
    echo "-------------------------------------------------------------------"
    LANG=C TZ=UTC date | tr -d '\n'
    echo -e " - Fabian Vogt <fabian@ritter-vogt.de>\n"
    echo "- Update to $1"
    echo ""
    exit 0
fi

if [[ $# -ne 4 ]]; then
    echo "Usage is different"
    exit 1
fi

repo=$1
version_from=$2
version_to=$3
type=$4

echo "-------------------------------------------------------------------"
LANG=C TZ=UTC date | tr -d '\n'
echo -e " - Fabian Vogt <fabian@ritter-vogt.de>\n"
echo "- Update to ${version_to}:"
echo "  * New $type release"
#echo "  * No changelog available"
echo "  * For more details please see:"
echo "  * http://code.qt.io/cgit/qt/${repo}.git/plain/dist/changes-${version_to}/?h=v${version_to}"
#echo "  * http://code.qt.io/cgit/qt/${repo}.git/plain/dist/changes-${version_to}/?h=${version_to}"
#echo "  * For more details about Qt 5.13 please see:"
#echo "    http://code.qt.io/cgit/qt/${repo}.git/plain/dist/changes-5.13.0/?h=5.13"
echo ""
