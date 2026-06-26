unit module BT::Bencode;

grammar Bencode {
    token TOP  { <val> }
    token val  { <int> | <bstr> | <list> | <dict> }
    token int  { 'i' $<num>=[\-? \d+] 'e' }
    token list { 'l' <val>* 'e' }
    token dict { 'd' [<bstr> <val>]* 'e' }
    token bstr { $<len>=[\d+] ':' $<bytes>=[ . ** { $<len>.Int } ] }
}

class Bencode::Actions {
    method TOP($/)  { make $<val>.made }
    method val($/)  { make ($<int> // $<bstr> // $<list> // $<dict>).made }
    method int($/)  { make $<num>.Int }
    method list($/) { make $<val>».made.List }
    method dict($/) { make Hash.new: $<bstr>».made Z $<val>».made }
    method bstr($/) {
        my $blob = $<bytes>.Str.encode('latin-1');
        make (try $blob.decode) // $blob; # try to decode or keep as blob
    }
}

sub bdecode(Blob $data) is export {
    Bencode.parse($data.decode('latin-1'), actions => Bencode::Actions).made;
}

multi sub bencode(Int $i --> Blob) is export {
    "i{$i}e".encode
}

multi sub bencode(Blob $b --> Blob) is export {
    "{$b.bytes}:".encode ~ $b
}

multi sub bencode(Str $s --> Blob) is export {
    bencode($s.encode)
}

multi sub bencode(List $l --> Blob) is export {
    'l'.encode ~ [~]($l>>.&bencode.encode) ~ 'e'.encode
}

multi sub bencode(Hash $h --> Blob) is export {
    'd'.encode ~ [~](do for $h.keys.sort -> $key {bencode($key) ~ bencode($h{$key})}) ~ 'e'.encode
}
