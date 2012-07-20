package openshift;
use Dancer ':syntax';
use Dancer::Plugin::REST;

prepare_serializer_for_format;

use CHI;
use Data::Dumper;
use HTML::TokeParser;
use LWP::UserAgent;
use Readonly;
use URI;

Readonly my $BASEURL => 'http://thecodelesscode.com';
Readonly my $CONTENTS => "$BASEURL/contents";
Readonly my $CASE => "$BASEURL/case";
Readonly my $CACHENAME => __PACKAGE__;
Readonly my $DURATION => "1h";

our $VERSION = '0.1';

my( $cache ) = CHI->new(
   driver => "File",
   namespace => $CACHENAME,
   root_dir => "misc/cache",
) or croak( "Unable to initialize cache: $!\n" );
info( "Initialized cache\n" );

hook 'before' => sub {
    var koans => getKoans( $cache );
};

get '/' => sub {
    template 'index';
};

get '/clear' => sub {
    warning( "Clearing cache." );
    $cache->clear;
};

get '/koan/:number.:format' => sub {
    vars->{koans}->{number}->{params->{number}};
};

sub getKoans {
    my( $cache ) = @_;

    debug( "Entering getKoans.\n" );

    my( $baseurl ) = config->{base_url} || $BASEURL;
    my( $contentsurl ) = "$baseurl/contents";
    my( $cache_name ) = $CACHENAME;
    my( $cache_duration ) = config->{cache_duration} || $DURATION;

    debug( "\$baseurl: $baseurl\n" );
    debug( "\$contentsurl: $contentsurl\n" );
    debug( "\$cache_name: $cache_name\n" );
    debug( "\$cache_duration: $cache_duration\n" );

    my( $koans ) = $cache->compute(
        $cache_name,
        $cache_duration,
        sub {
            debug( "Entering cacheKoans.\n" );
            info( "Cache miss, filling cache.\n" );

            my( $koans ) = {
                status => {
                    code => '',
                    message => '',
                },
                number => {},
                geekiness => {
                    not => [],
                    slightly => [],
                    moderately => [],
                    extremely => [],
                },
            };

            my( $ua ) = LWP::UserAgent->new();
            debug( "Instantiated LWP::UserAgent.\n" );
            $ua->timeout(10);
            $ua->env_proxy;
            debug( "Configured LWP::UserAgent.\n" );

            my( $uri ) = URI->new( $contentsurl );
            defined( $uri )
                or croak( "Unable to parse '$contentsurl': $!\n" );
            debug( "Parsed '$contentsurl'.\n" );

            my( $response ) = $ua->get( $uri );

            if ( $response->is_success ) {
                info( "Status " . $response->code . " from $contentsurl.\n" );
                my( $html ) = $response->decoded_content;

                my( $parser ) = HTML::TokeParser->new( \$html )
                    or croak( "Unable to parse HTML output: $!\n" );
                debug( "Instantiated HTML::TokeParser.\n" );
                $parser->empty_element_tags(1);

                while( my $toc = $parser->get_tag( "table" ) ) {
                    my( $tocattr ) = $toc->[1];
                    debug( Data::Dumper->Dump( [$tocattr], [qw(*tocattr)] ) );
                    if ( $tocattr->{class} eq "toc" ) {
                        debug( "This is the TOC class.\n" );
                    }
                    else {
                        debug( "This is not the TOC class.\n" );
                        next;
                    }

                    while( my $row = $parser->get_tag( "tr" ) ) {
                        my( $number, $title, $geekiness ) = ( 0, '', 'not' );

                        while( my $candidate = $parser->get_tag( "span", "a" ) ) {
                            my( $candidatetype, $candidateattr ) = ( $candidate->[0], $candidate->[1] );
                            if ( $candidatetype eq "span" ) {
                                debug( Data::Dumper->Dump( [$candidate], [qw(*candidate)] ) );
                                if ( defined( $candidateattr->{title} ) ) {
                                    if ( $candidateattr->{title} =~ /^(not|slightly|moderately|extremely) geeky$/ ) {
                                        $geekiness = $1;
                                        debug( "Looks like koan $number is $geekiness geeky.\n" );
                                    }
                                }
                            }
                            elsif ( $candidatetype eq "a" ) {
                                debug( Data::Dumper->Dump( [$candidate], [qw(*candidate)] ) );
                                if ( $candidateattr->{href} =~ m|^/case/(\d+)$| ) {
                                    $number = $1;
                                    $title = $parser->get_trimmed_text;
                                    debug( "Koan $number is called '$title'.\n" );

                                    # ok, now we have everything
                                    if ( $number =~ /^\d+$/ ) {
                                        $koans->{number}->{$number}->{title} = $title;
                                        $koans->{number}->{$number}->{geekiness} = $geekiness;

                                        # record geekiness
                                        push( @{$koans->{geekiness}->{$geekiness}}, $number );

                                        # get the content
                                        my( $content ) = getKoanContent( $number, $ua, $baseurl );
                                        if ( defined( $content ) ) {
                                            $koans->{number}->{$number}->{text} = $content->{text};
                                            $koans->{number}->{$number}->{date} = $content->{date};
                                            $koans->{number}->{$number}->{words} = $content->{words};
                                        }
                                    }
                                }
                            }
                        }

                        debug( "Done parsing table rows.\n" );
                    }
                }
            }

            $koans->{status}->{code} = $response->code;
            $koans->{status}->{message} = $response->message;

            debug( "Leaving cacheKoans.\n" );

            return( $koans );
        },
    );

    debug( Data::Dumper->Dump( [$koans], [qw(*koans)] ) );

    debug( "Leaving getKoans.\n" );

    return( $koans );
}

sub getKoanContent {
    my( $number, $ua, $baseurl ) = @_;

    debug( "Entering getKoans.\n" );

    my( $content ) = {
        text => '',
        words => 0,
        date => '',
    };

    my( $caseurl ) = "$baseurl/case/$number";

    my( $uri ) = URI->new( $caseurl );
    defined( $uri )
        or croak( "Unable to parse '$caseurl': $!\n" );
    debug( "Parsed '$caseurl'.\n" );

    my( $response ) = $ua->get( $uri );

    if ( $response->is_success() ) {
        my( $html ) = $response->decoded_content();

        my( $parser ) = HTML::TokeParser->new( \$html )
            or croak( "Unable to parse HTML output: $!\n" );
        debug( "Instantiated HTML::TokeParser.\n" );
        $parser->empty_element_tags(1);

        while ( my $div  = $parser->get_tag( "div" ) ) {
            my( $divattr ) = $div->[1];
            next unless defined( $divattr->{class} );
            debug( Data::Dumper->Dump( [$divattr], [qw(*divattr)] ) );
            if ( $divattr->{class} eq "koan" ) {
                debug( "Found the koan.\n" );

                # $content->{text} = $parser->get_trimmed_text( "/div" );
                $content->{text} = sanitizeKoan( $parser->get_text( "/div" ) );
            }
            elsif ( $divattr->{class} eq "signature" ) {
                debug( "Found the signature.\n" );
                if ( $parser->get_trimmed_text( "/div" ) =~ /-- (\d+ \w+ \d+) - (\d+) words/ ) {
                    my( $date, $words ) = ( $1, $2 );
                    debug( "\$date: '$date', \$words: $words\n" );
                    $content->{date} = $date;
                    $content->{words} = $words;
                    last;
                }
            }
        }
    }

    debug( Data::Dumper->Dump( [$content], [qw(*content)] ) );
    debug( "Leaving getKoanContent.\n" );

    return( $content );
}

sub sanitizeKoan {
    my( $raw ) = @_;

    debug( "Entering sanitizeKoan" );

    my( @lines ) = split( "\n\n+", $raw );
    debug( "Found " . scalar( @lines ) . " lines of raw koan" );
    my( $cooked ) = '';

    while ( @lines ) {
        my $line = shift( @lines );
        chomp( $line );
        debug( "Sanitizing '$line'" );
        # eliminate internal newlines
        $line =~ s/\n+/ /g;
        if ( $line !~ /\[IMG\]/ ) {
            # strip the IMG placeholders
            debug( "Capturing '$line'" );
            $cooked .= "$line\n\n";
        }
    }

    # final cleanup
    chomp( $cooked );
    $cooked =~ s/\s+$//;

    debug( "Leaving sanitizeKoan" );

    return( $cooked );

}

true;
