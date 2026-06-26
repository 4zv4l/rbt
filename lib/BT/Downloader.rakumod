unit class BT::Downloader;

use BT::TorrentFile;
use BT::Tracker;
use BT::Peers;
use BT::PiecesManager;

method download(Str $filepath, Str $output-path, UInt $pipeline-size = 15 --> Supply) {
    my BT::TorrentFile   $torrent        .= new: $filepath;
    my BT::Tracker       $tracker        .= new: uri          => $torrent.tracker-url;
    my BT::PiecesManager $pieces-manager .= new: torrent-name => $torrent.name,
					         files        => $torrent.files,
					         pieces       => $torrent.pieces,
                                                 piece-length => $torrent.piece-length,
                                                 output-path  => $output-path;
    my Channel           $todo-chan      .= new;
    my Channel           $done-chan      .= new;
    my Supplier          $broadcast      .= new;
    my SetHash           $peers          .= new;

    my $total-length = $torrent.files.map(*.<length>).sum;
    for (0 ..^ $torrent.pieces.elems).pick(*) -> $index {
        next if $pieces-manager.bitfield{$index};
        # handle last piece which size might be different
        my $p-len = ($index == $torrent.pieces.elems - 1)
			?? ($total-length % $torrent.piece-length || $torrent.piece-length)
			!! $torrent.piece-length;
        $todo-chan.send: %( :$index, length => $p-len );
    }
    
    supply {	
	whenever $tracker.fetch-peers -> @peers {
	    my $new-peers = @peers.Set (-) $peers;
	    for $new-peers.keys -> $address {
		BT::Peers.new(
		    :$address,
		    :info-hash($torrent.info-hash),
		    :peer-id($torrent.peer-id),
		    :$pieces-manager,
		    :$todo-chan,
		    :$done-chan,
		    :broadcast-feed($broadcast.Supply),
		    :max-pipeline($pipeline-size)
		).work.then: { $peers.unset($address) };
		$peers.set($address);
	    }
	}
	
	whenever $done-chan.Supply -> %chunk {
	    $pieces-manager.write: %chunk;
	    $pieces-manager.bitfield.set(%chunk<index>);
	    $broadcast.emit(%chunk<index>);
	    emit %( $pieces-manager.progress, %(:$peers));
	    done if $pieces-manager.is-complete;
	}

	emit $pieces-manager.progress;
    }
}
