unit class BT::TorrentFile;

use BT::Bencode;
use Digest::SHA1::Native;
use URI;

has Blob $.info-hash;
has Str  $.name;
has Str  $.tracker-url;
has Str  $.peer-id;
has UInt $.piece-length;
has UInt $.total-length;
has      @.pieces;
has      @.files;
has      $.raw-content;

method new(Str $filepath where *.IO.f) {
    self.bless: raw-content => bdecode($filepath.IO.slurp(:bin));
}

submethod TWEAK {
    my %info       = $!raw-content<info>;
    $!name         = %info<name>;
    $!info-hash    = sha1(bencode(%info));
    $!peer-id      = 'RBTTT' ~ ('a'..'z').roll(15).join;
    $!piece-length = %info<<'piece length'>>;
    @!pieces       = %info<pieces>.list.rotor(20).map: { Blob.new(@^p) };
    @!files        = %info<files>:exists
		         ?? %info<files>.map: {%(:path(.<path>.join('/')), :length(.<length>))}
                         !! [ %(:path($!name), :length(%info<length>)), ];
    $!total-length = @!files>>.<length>.sum;
    $!tracker-url  = do given URI.new($!raw-content<announce>) -> $uri {
	when $uri.scheme eq <http https>.any {
	    $uri ~ '?info_hash='  ~ $!info-hash.list.fmt('%%%02X', '')
                 ~ '&peer_id='    ~ $!peer-id
                 ~ '&port='       ~ 0
                 ~ '&uploaded='   ~ 0
                 ~ '&downloaded=' ~ 0
                 ~ '&compact='    ~ 1
                 ~ '&left='       ~ $!total-length;
	}
	default { note "{$uri.scheme} trackers are not yet implemented." and exit 1 }
    };
}
