#!/usr/bin/env bash

Help() {
	cat <<EOF
Usage: $(basename $0) [-s <chunkSize>] source destination

-s <chunkSize>: the size of the chunks to split your uploaded file into. Defaults to 10M. Bigger chunks will (probably?) be faster, at the expense of wasting more time were your connection to be interrupted.
It can have a BKMGT suffix but it must be an integer, because I'm not dealing with floating point math in Bash and I don't want to depend on awk, as silly as that may be.

source is the file to be uploaded, while destination is the full WebDAV endpoint of your desired destination, such as https://example.com/nextcloud/remote.php/dav/files/nix/Examples/foobar.txt .

An application password _must_ be provided via the NEXTCLUPLOAD_SECRET environment variable.
EOF
}

while getopts ":s:h" option; do
	case $option in
		s)
			chunkSize=$OPTARG;;
		h)
			;&
		\?)
			Help
			exit;;
	esac
done
shift $((OPTIND-1))

validateSourceFile() {
	source=$1
	if [[ ! -r $source || ! -f $source ]] ; then
		echo "Source file must exist, be a file, and be readable."
		exit -1
	fi
	local filename=$(basename $source)
	local hash=$(md5sum $source | cut -d " " -f1)
	name="$hash-$filename"
}

parseDestinationArgument() {
	destination=$1
	host=${1%/remote.php/dav/*}/remote.php/dav/
	local path=${1#*/remote.php/dav/files/}
	user=${path%%/*}
	if [[ -z $host || -z $user ]] ; then
		echo "Please specify a valid destination."
		exit -1
	fi
	destinationHeader="Destination: Destination $destination"
	destinationHeaderMove="Destination: $destination"
}

checkSecret() {
	if [[ -z $NEXTCLUPLOAD_SECRET ]] ; then
		echo "A secret, or application password, must be provided."
		exit -1
	fi
}

validateChunkSize() {
	if [[ -n $1 ]] ; then
		if echo $1 | grep -E '^[0-9]+[BKMGT]?$' >/dev/null ; then
			local number=$(echo $1 | grep -o -E '^[0-9]+')
			local suffix=${1:0-1}
			case $suffix in
				T) ((number*=1024)) ;&
				G) ((number*=1024)) ;&
				M) ((number*=1024)) ;&
				K) ((number*=1024)) ;;
			esac
			chunkSize=$number
		else
			echo "Please use an appropriate size."
			exit -1
		fi
	fi
}

parseResumeEntries() {
	while IFS= read -r entry; do
        href=$(grep -o -P '<d:href>(.+?)</d:href>' <<< $entry | sed -E 's/<\/?d:href>//g')
        number=${href##*/}
        if [[ -z $number || $number == ".file" ]] ; then
            continue
        fi
        if [[ $number > $last ]] ; then
            last=$number
        fi
        resumeChunkSize=$(grep -o -P '<d:getcontentlength>\d+</d:getcontentlength>' <<< $entry | sed -E 's/<\/?d:getcontentlength>//g')
        ((uploaded+=resumeChunkSize))
        if [[ -z $firstChunkSize ]] ; then
            firstChunkSize=$resumeChunkSize
        fi
    done <<< "$1"
}

determineSizes() {
	fileSize=$(du -b --apparent-size $1 | cut -f1)
	if [[ -z $chunkSize ]] ; then
	    chunkSize=$firstChunkSize
	fi
	if [[ -z $chunkSize ]] ; then
		chunkSize=$(( fileSize < 10*1024*1024 ? fileSize : 10*1024*1024 ))
	fi

	chunks=$(( (fileSize+chunkSize-1)/chunkSize ))
}

validateSourceFile $1
parseDestinationArgument $2
checkSecret
validateChunkSize $chunkSize

# Get the contents of the expected upload folder
test="$(curl -u $user:$NEXTCLUPLOAD_SECRET "${host}uploads/${user}/$name" -X PROPFIND)"
uploaded=0
last=0
if grep -qs -F "<s:exception>Sabre\DAV\Exception\NotFound</s:exception>" <<< "$test" ; then # Fresh upload, preparations are needed
	echo "Creating upload folder"
	curl -X MKCOL -u $user:$NEXTCLUPLOAD_SECRET --header "$destHeader" "${host}uploads/${user}/$name"
else
	echo "Resuming upload..."
    entries=$(grep -o -P '<d:response>(.+?)</d:response>' <<< $test)
    parseResumeEntries "$entries"
fi

determineSizes $source

echo "Start uploading from byte $uploaded"
while ((uploaded<fileSize)) ; do
    ((last++))
    echo -n "Uploading chunk $last from byte $uploaded/$fileSize"
    fileId=$(printf %05d $last)
    ((remaining=fileSize-uploaded))
    ((chunkSize=(chunkSize<remaining)?chunkSize:remaining))
    tail -c +$((uploaded+1)) $source | head -c $chunkSize | \
        curl --data-binary @- -X PUT -u "$user:$NEXTCLUPLOAD_SECRET" --header "$destinationHeader" --header "OC-Total-Length: $fileSize" "${host}uploads/${user}/$name/$fileId"
    ((uploaded+=chunkSize))
done

curl -X MOVE -u $user:$NEXTCLUPLOAD_SECRET --header "$destinationHeaderMove" --header "OC-Total-Length: $fileSize" "${host}uploads/${user}/${name}/.file"