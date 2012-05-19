#!/bin/sh
# -x

# on Windows 7
ipaDir="$USERPROFILE/Music/iTunes/iTunes Media/Mobile Applications/"

#ipaDir="/cygdrive/c/tmp/tmpipa"
outDir="/cygdrive/c/tmp/tmpipap"

UNZIP=unzip
IPAINFOPL=ipainfo.pl

plistFile=iTunesMetadata.plist

while getopts "?hxd:o:p:" flag
do
#		echo "$flag" $OPTIND $OPTARG
		case "$flag" in
				d)	ipaDir="$OPTARG";;
				o)	outDir="$OPTARG";;
				p)	prefix="$OPTARG";;
				x)	set -x;;
				[?h])	echo >&2 "Usage: $0 [ -?hx ] [ -p <prefix> ] [ -d <ipa-dir> ] [ -o <out-dir> ]"
						exit 1;;
		esac
done
shift $((OPTIND-1))

cd "$ipaDir"

for fname in "$prefix"*.ipa
do
		echo "Extracting plist from $fname"
		$UNZIP -q -p "$fname" "$plistFile" > "$outDir/$fname.plist"
done

cd "$outDir"

$IPAINFOPL
