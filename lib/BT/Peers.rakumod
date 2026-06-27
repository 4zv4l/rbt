unit class BT::Peers;

use BT::PiecesManager;

has Str               $.address;
has Str               $.peer-id;
has Blob              $.info-hash;
has Bool              $!choked       = True;
has SetHash           $!peer-pieces .= new;
has BT::PiecesManager $.pieces-manager;
has Channel           $.todo-chan;
has Channel           $.done-chan;
has Supply            $.broadcast-feed;
has Int               $.max-pipeline = 15;
has                   %!task;

enum MessageID <Choke Unchoke Interested NotInterested Have Bitfield Request Piece Cancel>;

method work(--> Supply) {
    supply {
        whenever IO::Socket::Async.connect(|$!address.split(':')) -> $conn {
            my $handshake = Blob.new(19)
                          ~ "BitTorrent protocol".encode('ascii')
                          ~ Blob.new(0 xx 8)
                          ~ $!info-hash
                          ~ $!peer-id.encode('ascii');
            $conn.write($handshake);

            my Buf $buffer      .= new;
            my Bool $handshaked  = False;

            # update peer we got a new chunk
            whenever $!broadcast-feed -> $index {
                if $handshaked {
                    my Buf $have-msg .= new;
                    $have-msg.write-uint32(0, 5, BigEndian); 
                    $have-msg.write-uint8(4, 4); 
                    $have-msg.write-uint32(5, $index, BigEndian);
                    $conn.write($have-msg);
                }
            }

            # receive data loop
            whenever $conn.Supply(:bin) -> $chunk {
                $buffer.append($chunk);

                # handle handshake + interested
                if !$handshaked and $buffer.elems >= 68 {
                    my $peer-hash = $buffer.subbuf(28, 20);
                    unless $peer-hash.list eqv $!info-hash.list {
                        $conn.close;
                        done;
                    }
                    $buffer .= subbuf(68);
                    $handshaked = True;

                    my Buf $interested-msg .= new;
                    $interested-msg.write-uint32(0, 1, BigEndian);
                    $interested-msg.write-uint8(4, 2);
                    $conn.write($interested-msg);
                }
		
                # other messaging handling
                self!process-buffer($buffer, $conn) if $handshaked;

                LAST { 
                    $!todo-chan.send(%( index => %!task<index>, length => %!task<length> )) if %!task;
                    done;
                }
                QUIT {
		    default {
			$!todo-chan.send(%( index => %!task<index>, length => %!task<length> )) if %!task;
		    }
                }
            }
        }
    }
}

# request task from Downloader channel
# send multiple request to download 1 full piece
method !request-work(IO::Socket::Async $conn) {
    return if $!choked;

    if !%!task {
        my $attempts = 0;
        while True {
            if $!todo-chan.poll -> %w {
                if %w<index> ∈ $!peer-pieces {
                    %!task = index      => %w<index>,
                             length     => %w<length>,
                             buf        => Buf.new(0 xx %w<length>),
                             req-offset => 0,
                             downloaded => 0,
                             pipeline   => 0;
                    last;
                } else {
                    $!todo-chan.send(%w);
                    $attempts++;
                }
            } else {
                last;
            }
        }
    }

    while %!task && %!task<pipeline> < $!max-pipeline && %!task<req-offset> < %!task<length> {
        my $len = min(16384, %!task<length> - %!task<req-offset>);
        
        my Buf $req = Buf.new(0 xx 17);
        $req.write-uint32(0, 13, BigEndian);
        $req.write-uint8(4, 6);
        $req.write-uint32(5, %!task<index>, BigEndian);
        $req.write-uint32(9, %!task<req-offset>, BigEndian);
        $req.write-uint32(13, $len, BigEndian);
        
        $conn.write($req);
        
        %!task<req-offset> += $len;
        %!task<pipeline>++;
    }
}

method !process-buffer(Buf $buffer is rw, IO::Socket::Async $conn) {
    while $buffer.elems >= 4 {
        my $len = $buffer.subbuf(0, 4).read-uint32(0, BigEndian);

        if $len == 0 { $buffer .= subbuf(4); next } 
        last if $buffer.elems < 4 + $len; 

        my $id      = $buffer[4];
        my $payload = $buffer.subbuf(5, $len - 1);

        given MessageID($id) {
            when Choke    { $!choked = True; $!todo-chan.send(%( index => %!task<index>, length => %!task<length> )); %!task = () }
            when Unchoke  { $!choked = False; self!request-work($conn) }
            when Have     { self!handle-have($payload); self!request-work($conn) }
            when Bitfield { self!handle-bitfield($payload); self!request-work($conn) }
            when Piece    { self!handle-piece($payload, $conn) }
            when Request  { self!handle-request($payload, $conn) }
        }

        $buffer .= subbuf(4 + $len);
    }
}

# peer tells us one peice he has
method !handle-have(Blob $payload) {
    my $index = $payload.read-uint32(0, BigEndian);
    $!peer-pieces.set($index);
}

# peer tells us what pieces he has
method !handle-bitfield(Blob $payload) {
    for 0 ..^ $payload.elems -> $i {
        for 0 .. 7 -> $bit {
            if $payload[$i] +& (1 +< (7 - $bit)) {
                $!peer-pieces.set( ($i * 8) + $bit );
            }
        }
    }
}

# peer gives us a piece
method !handle-piece(Blob $payload, IO::Socket::Async $conn) {
    return unless %!task;

    my $begin = $payload.read-uint32(4, BigEndian);
    my $blob  = $payload.subbuf(8);

    %!task<buf>.splice($begin, $blob.bytes, $blob);
    
    %!task<downloaded> += $blob.bytes;
    %!task<pipeline>--;

    if %!task<downloaded> == %!task<length> {
        $!done-chan.send: %( index => %!task<index>, begin => 0, blob => %!task<buf> );
        %!task = ();
    }
    
    self!request-work($conn);
}

# peer asks us for a piece
method !handle-request(Blob $payload, $conn) {
    my $index  = $payload.read-uint32(0, BigEndian);
    my $begin  = $payload.read-uint32(4, BigEndian);
    my $length = $payload.read-uint32(8, BigEndian);
    return unless $!pieces-manager.bitfield{$index};

    my Blob $block  = $!pieces-manager.read($index, $begin, $length);
    my Buf  $reply .= new;
    $reply.write-uint32(0, 9 + $block.bytes, BigEndian); 
    $reply.write-uint8(4, 7);                            
    $reply.write-uint32(5, $index, BigEndian);          
    $reply.write-uint32(9, $begin, BigEndian);          
    $reply.append($block);
    $conn.write($reply);
}
