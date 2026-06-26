unit class BT::PiecesManager;

use Digest::SHA1::Native;

has         $.torrent-name;
has         @.files;
has         @.pieces;
has         $.piece-length;
has SetHash $.bitfield = .new;

multi method new(:$torrent-name, :@files is copy, :@pieces, :$piece-length, :$output-path) {
    my $global-offset = 0;
    for @files -> %file {
	my $io            = ($output-path ~ '/' ~ %file<path>).IO;
	mkdir $io.dirname;
	%file<handle>     = $io.open(:rw);
	%file<offset>     = $global-offset;
	%file<downloaded> = 0;
	$global-offset   += %file<length>;
    }
    self.bless: :$torrent-name, :@files, :@pieces, :$piece-length;
}

submethod TWEAK { self.verify-files(); }

method verify-files() {
    for 0 ..^ @!pieces.elems -> $i {
        my $data = self.read($i, 0, $!piece-length);
        $!bitfield.set($i) if sha1($data) eqv @!pieces[$i];
    }
 }

# %chunk<index begin blob>
# index = which piece
# begin = index of subpiece
# blob  = actual bytes to write
method write(%chunk) {
    my $global-pos = (%chunk<index> * $!piece-length) + %chunk<begin>;
    my $data       = %chunk<blob>;
    my $bytes-left = $data.bytes;
    my $data-pos   = 0; # Tracker for where we are inside the chunk's Blob

    for @!files -> %file {
        last if $bytes-left <= 0;
        next if %file<offset> + %file<length> <= $global-pos;

        my $file-pos    = $global-pos - %file<offset>;
        my $write-count = min($bytes-left, %file<length> - $file-pos);

        %file<handle>.seek($file-pos); 
        %file<handle>.write($data.subbuf($data-pos, $write-count));

        %file<downloaded> += $write-count;
        $global-pos       += $write-count;
        $data-pos         += $write-count;
        $bytes-left       -= $write-count;
    }
}

method read(Int $index, Int $begin, Int $length --> Buf) {
    my $global-pos = ($index * $!piece-length) + $begin;
    my $bytes-left = $length;
    my Buf $data  .= new;

    for @!files -> %file {
        last if $bytes-left <= 0;
        next if %file<offset> + %file<length> <= $global-pos;

        my $file-pos   = $global-pos - %file<offset>;
        my $read-count = min($bytes-left, %file<length> - $file-pos);

        %file<handle>.seek($file-pos);
        my $chunk = %file<handle>.read($read-count);

        $data.append($chunk);
        $global-pos += $chunk.bytes; 
        $bytes-left -= $chunk.bytes; 
    }

    return $data;
}

# from SetHash to Bitfield
method pack-bitfield(--> Blob) {
    my $num-bytes = (@!pieces.elems + 7) div 8;
    my Buf $buf .= new(0 xx $num-bytes);
    for $!bitfield.keys -> $index {
        my $byte-index = $index div 8;
        my $bit-offset = $index % 8;
        $buf[$byte-index] +|= 128 +> $bit-offset;
    }
    return $buf;
}

# return Hash with infos to be used
# to show progress by the main app
method progress(--> Hash()) {
    :$!torrent-name,
    :$!bitfield,
    :total-pieces(@!pieces.elems),
    :@!files;
}

method is-complete(--> Bool) {
    $!bitfield.elems == @!pieces.elems;
}
