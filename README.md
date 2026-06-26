# rbt

BitTorrent client in Raku

# Install

You will need `raku`.

You will also need to install those Raku modules using `zef`:

- [Digest::SHA1::Native](https://raku.land/zef:bduggan/Digest::SHA1::Native)
- [Cro::HTTP::Client](https://cro.raku.org/docs/reference/cro-http-client)
- [URI](https://raku.land/zef:raku-community-modules/URI)

# Usage

Its pretty basic and straightforward:

``` shell
$ ./bin/rbt 
Usage:
  ./bin/rbt [-o|--output-path=<Str>] [--pipeline[=UInt]] <file>
  
    <file>                    .torrent file to download
    -o|--output-path=<Str>    where to download the file(s) [default: '.']
    --pipeline[=UInt]         pipeline size [default: 15]
```

Example of when downloading:

``` shell
$ ./bin/rbt -o ./tmp ./resources/debian.torrent 
debian-12.6.0-amd64-netinst.iso:
[░░ ░░ ░  ░ ░  ░ ░░   ░░░ ░   ░░   ░  ░ ░  ░ ░░  ░░░  ░ ░    ░ ] 103/2524 pieces
41 peers
```

# TODO

- Allow users to specify a port, to send it to the tracker and listen for peers
- Better handling of the last fiew pieces to download
