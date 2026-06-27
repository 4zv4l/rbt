unit class BT::Tracker;

use Cro::HTTP::Client;
use BT::Bencode;

has Str  $.uri;

# fetch peers every $!timeout
# return them as array of ipv4:port
method fetch-peers(--> Supply) {
    my $supplier = Supplier.new;
    start {
        loop {
            my $resp  = await Cro::HTTP::Client.get($!uri);
            my %reply = bdecode(await $resp.body-blob);
            my @peers = %reply<peers>.list.rotor(6).map: -> ($a, $b, $c, $d, $p1, $p2) {
                "$a.$b.$c.$d:{ ($p1 +< 8) +| $p2 }"
            };
            $supplier.emit(@peers);
            await Promise.in(%reply<interval> // 1800);
        }
    }
    return $supplier.Supply;
}
