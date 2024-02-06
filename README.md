# nextclUpload.sh
This thing is a Bash script that allows you to upload big files to any Nextcloud instance using the chunked upload api (v2). Requires `curl` and very little else, if anything.
## Usage
```
Usage: nextclUpload.sh [-s <chunkSize>] source destination

-s <chunkSize>: the size of the chunks to split your uploaded file into. Defaults to 10M. Bigger chunks will (probably?) be faster, at the expense of wasting more time were your connection to be interrupted.

source is the file to be uploaded, while destination is the full WebDAV endpoint of your desired destination, such as https://example.com/nextcloud/remote.php/dav/files/nix/Examples/foobar.txt .

An application password _must_ be provided via the NEXTCLUPLOAD_SECRET environment variable.
```

## FAQ
There are none.

## QYSBA
Questions you should be asking include the following:

> Does it work?

Yes!

> Is it stable, solid, and well-written?

Hell no!

> Should I be using this?

...Probably not. Works for me, but I haven't tested it much.

> Shouldn't there be more stuff in this readme?

Yup. It's late, though, so I'm going to sleep.