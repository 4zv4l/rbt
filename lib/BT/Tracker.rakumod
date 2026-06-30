unit class BT::Tracker;

use Cro::HTTP::Client;
use BT::Bencode;

has Str  $.uri;

# fetch peers every $!timeout
# return them as array of ipv4:port
method fetch-peers(--> Supply) {
    supply {
        sub fetch() {
            whenever Cro::HTTP::Client.get($!uri) -> $resp {
                whenever $resp.body-blob -> $blob {
                    my %reply = bdecode($blob);
                    emit %reply<peers>.list.rotor(6).map: -> ($a, $b, $c, $d, $p1, $p2) {
                        "$a.$b.$c.$d:{ ($p1 +< 8) +| $p2 }"
                    };
                    whenever Promise.in(%reply<interval> // 1800) { fetch() }
                }
            }
        }
        fetch();
    }
}
