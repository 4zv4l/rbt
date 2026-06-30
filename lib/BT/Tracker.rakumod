unit class BT::Tracker;

use Cro::HTTP::Client;
use BT::Bencode;

has Str  $.uri;

# fetch peers every $!timeout
# return them as array of ipv4:port
method fetch-peers(--> Supply) {
    supply {
        sub fetch() {
            whenever Cro::HTTP::Client.get($!uri, timeout => 5) -> $resp {
		note "[+] $?FILE: whenever Cro get: start";
		LEAVE note "[+] $?FILE: whenever Cro get: end";
		
                my $body-p = $resp.body-blob;
                whenever Promise.anyof($body-p, Promise.in(5)) -> $ {
		    note "[+] $?FILE: whenever anyof body: start";
		    LEAVE note "[+] $?FILE: whenever anyof body: end";
		    
                    if $body-p.status == Kept {
			note "[*] $?FILE: whenever body OK";
                        my %reply = bdecode($body-p.result);
                        
                        emit %reply<peers>.list.rotor(6).map: -> ($a, $b, $c, $d, $p1, $p2) {
                            "$a.$b.$c.$d:{ ($p1 +< 8) +| $p2 }"
                        };
                        whenever Promise.in(20 // %reply<interval> // 1800) { fetch() }
                    } else {
			note "[*] $?FILE: whenever body NOT OK!!!";
                        whenever Promise.in(15) { fetch() }
                    }
                }
            }
        }
        fetch();
    }
}
