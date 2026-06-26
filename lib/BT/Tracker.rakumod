unit class BT::Tracker;

use Cro::HTTP::Client;
use BT::Bencode;

has Str  $.uri;

# fetch peers every $!timeout
# return them as array of ipv4:port
method fetch-peers(--> Supply) {
    my $interval = Promise.in(0);
    supply {
	whenever $interval {
	    my $resp  = await Cro::HTTP::Client.get($!uri);
	    my %reply = bdecode(await $resp.body-blob);
	    my @peers = %reply<peers>.list.rotor(6).map: -> ($a, $b, $c, $d, $p1, $p2) {
		"$a.$b.$c.$d:{ ($p1 +< 8) +| $p2 }"
	    };
	    $interval = Promise.in(%reply<interval> // 1800);
	    emit @peers;
	}	
    }
}
