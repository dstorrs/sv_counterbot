package Forum::SufficientVelocity;

use strict;
use warnings;
use feature ':5.10';

use Data::Dumper;
use HTML::Element;
use Log::Log4perl qw(:easy);
use HTML::TreeBuilder 5 -weak;

use constant BASE_URL => 'https://forums.sufficientvelocity.com/';
use constant VERBOSE => 0;

#Log::Log4perl->easy_init( $DEBUG );
Log::Log4perl->easy_init( $ERROR );

our $VERSION = 1.2;
our $POSTS_PER_PAGE = 25; # Deliberately made a package variable

our (@ISA, @EXPORT_OK, @EXPORT);
BEGIN {
	require Exporter;
	@ISA = qw(Exporter);
	
	our @EXPORT   = qw/init generate_report/;
	
	our @EXPORT_OK   = qw/generate_report
						  get_page
						  make_root
						  get_page_urls_after
						  get_posts
						  author_ref
						  get_id
						  make_plan
						  init
						  text_of
						  content_text
						  remove_quote_blocks
						  get_votes
						  tally_plans
						  canonize_plan_name
						  vote_type
						 /;
	our %EXPORT_TAGS = (all => [ qw/generate_report
									get_page
									make_root
									get_posts
									get_page_urls_after
									author_ref
									get_id
									make_plan
									init
									text_of
									content_text
									remove_quote_blocks
									get_votes
									tally_plans
									canonize_plan_name
									vote_type
								   /
							   ]
					);
}

###----------------------------------------------------------------------

my $PLAN_NAME_PREFIX = qr/^\s*\[[+X-]\]\s*/i;

###----------------------------------------------------------------------

{
	my $data;

	sub _get_data {
		my $key = shift;
		die "You didn't call init()!\n" unless $data;
		return $data->{$key};
	}
	
	sub first_post_id { _get_data('first_post_id') }
	sub exclude_users { _get_data('exclude_users') }
	sub first_url     { _get_data('first_url')     }
	sub stop_id       { _get_data('stop_id') || 0  }

	sub init {
		my %args = @_;

		#    Options:
		# first_url      => 'http...',
		# first_post_id  => 2,
		# last_post_id   => 27,
		# exclude_users  => [ qw/bob tom sue/ ], #  Will be converted to qw/@bob @tom @sue/ if it isn't already


		unless ( $args{first_url} && $args{first_url} =~ /^\s*http/ ) {
			die "Must specify a first page URL using: first_url => 'http / http...'"
		}
		
		$args{first_url} =~ s/^\s*//;
		$args{first_url} =~ s/\s*$//;
		
		$args{first_post_id} ||= 0;
		$args{last_post_id}  ||= $args{stop_id} || 0;
		
		$args{ exclude_users } ||= [];

		#    usernames should start with '@', but only one '@'.  Turn
		#    the array ref into a hash ref for easy reference
		#
		my @names = @{ $args{ exclude_users } };
		$args{ exclude_users } = {
			map { $_ => 1 }
				map { /^@/ ? $_ : '@' . $_ }
					@names
		};
		
		$data = \%args;
	}
}

###----------------------------------------------------------------------

sub generate_report {

	my $root = make_root( first_url() );
	output_report(                              # Show the report 
		format_plans(                           # Generate the text of the report
			tally_plans(                        # Count the votes
				map { make_plan($_) }           # Generate a voting plan for each post
					map { get_posts($_) }
						$root, map { make_root($_) }
							get_page_urls_after( $root )
								
						)
		)
	);
}



###----------------------------------------------------------------------

sub has_cache {

}

###----------------------------------------------------------------------

sub make_root {  
	my $url = shift;
	my $root = HTML::TreeBuilder->new_from_content( get_page($url) );
	$root->objectify_text;
	return $root;
}

###----------------------------------------------------------------------

sub get_page_urls_after {
	my $root = shift || die "No page node specified in get_page_urls()";

	my $nav = $root->look_down(
		_tag => 'div',
		class => 'PageNav'
	);
	return () unless $nav;
		
	my ($base_url, $sentinel, $last_page, $current_page) = 
		map { chomp; $_ }
			map {  $nav->attr($_) }
				qw/data-baseurl data-sentinel data-last data-page/;

	if ( stop_id() ) {
		#    If the caller wants us to stop at a specific post, figure
		#    out what page that will be on
		$last_page = int 1 + stop_id() / $POSTS_PER_PAGE;
	}

	$base_url =~ s/\Q$sentinel\E//;
	$base_url = BASE_URL . $base_url;
	$current_page++;  #  We already have the current one, so skip it

	return () if $current_page > $last_page;
	my @urls = map { $base_url . $_ }  ( $current_page .. $last_page );

	return @urls;
}

###----------------------------------------------------------------------

sub author_ref {
	my $author = shift || die "no author specified in 'author_ref'";

	return $author if $author =~ /^@/;
	return '@' . $author;
}

###----------------------------------------------------------------------

sub get_id {
	my $p = shift ||  die "No post object (HTML::Element based) supplied in get_id()";
	
	my $text = '';
	eval {
		#    If we get a 
		$text = $p->look_down(_tag => 'div', class => 'publicControls')->look_down(_tag => '~text')->attr('text');
	};
	if ( $@ ) { $text = '' }  # Not worth using Try::Tiny for this
	
	my ($id) =  $text =~ /(\d+)/;  #  Cut off the leading '#'
	return $id;
}

###----------------------------------------------------------------------

sub make_plan {
	my $post = shift || die "no post object specified";

	my $author = author_ref( $post->attr('data-author') );
	my $id = get_id( $post );

	DEBUG  "author, id: '$author', '$id'";

	return if exclude_users()->{ $author };
	if ( $id < first_post_id() ) {
		DEBUG "ID is $id, first is ", first_post_id(), ".  Skipping.";
		return;
	}
	
	remove_quote_blocks($post);  # Ignore text that was quoted from an earlier post

	#    Retrieve the link to the post
	my $link = $post->look_down(
		_tag => 'a',
		class => qr/hashPermalink/,
		href => qr<posts/\d+/>
	)->attr('href');
	unless ( $link =~ /^http/ ) {
		$link = BASE_URL . $link;  
	}
	DEBUG "link is $link";
	
	my $plan = {
		post   => $post,
		author => $author,
		link   => $link,
		id     => $id,
		text   => content_text( $post ),
	};
	
	#    Add the votes after creating the post so that we only have to
	#    do text_of once.
	$plan->{votes} = get_votes( $plan );
	
	return $plan;
}

###----------------------------------------------------------------------

sub remove_quote_blocks {
	my $post = shift || die "No post object (HTML::Element based) supplied in remove_quote_blocks()";
	
	$_->delete for $post->look_down(
		_tag => 'div',
		class => qr/\bbbCodeQuote\b/,
	);
	return $post;
}

###----------------------------------------------------------------------

sub text_of {
	my $node = shift;

	my $text = 'NO TEXT FOUND';
	if ( $node->tag eq '~text' ) {
		$text = $node->attr('text');
	}
	else {
		$text = join("\n", map { text_of($_) } $node->content_list);
	}

	VERBOSE && DEBUG "### BEFORE modding, Text is: '$text'";
	
	#    SV has an annoying habit of putting \n and whitespace in
	#    front of every open tag and behind ever close tag.  So, if
	#    you start with this:
	#
	#        [X] Plan do [i]all[/i] the things
	#
	#    after you remove the tags you SHOULD get this:
	#
	#        [X] Plan do all the things is actually this:
	#
	#    but actually you get this:
	#
	#        [X] Plan do
	#         all
	#        the things
	#
	my @chunks =
			map { s/\n//smg; $_ }
				grep { $_ }
					split /\n\n/sm, $text;
	VERBOSE && DEBUG "chunks is: ", Dumper \@chunks;

	$text = join("\n\n", @chunks);
	VERBOSE && DEBUG "### AFTER modding, Text is: \n'$text'";
	
	return $text;
}

###----------------------------------------------------------------------

sub content_text {
	my $post = shift or die "No post object (HTML::Element derived) specified in content_text()"; 

	my $text = text_of(
		$post->look_down(
			_tag => 'div',
			class => 'messageContent'
		)
	);
	
	return clean_text( $text );
}

###----------------------------------------------------------------------

sub clean_text {
	my $text = shift;
	
	$text =~ s/ //g;    # 
	$text =~ s/^\s*//;  # Strip non-printing character that SV likes to 
	$text =~ s/\s*$//;  # randomly add, plus leading and trailing whitespace

	return $text;
}

###----------------------------------------------------------------------

sub get_posts {
	my $page = shift or die "No page object (HTML::Element derived) specified in get_posts";

	my $stop_id = stop_id();

	my $filter = sub {
		my $p = shift;
		DEBUG "Stop id, post id: $stop_id, ", get_id($p);
		return $p unless $stop_id;
		return if get_id($p) > $stop_id;
		return $p;
	};
	

	my @posts = 
		grep { defined $filter->($_) }
			$page->look_down(
				_tag => 'li',
				id => qr/post-\d+/
			);

	return @posts;
}

###----------------------------------------------------------------------

sub get_votes {
	my $plan = shift || die "No plan specified in get_votes";
	my $text = $plan->{text};

	#    Votes can now have: '[X]', '[x]', '[+]', or '[-]'.  The first
	#    three are all votes for a plan, while '[-]' means 'remove me
	#    from this plan'.  The votes-for signs will all be converted
	#    to '[X]'
	#

	DEBUG "in get_votes, text is: $text";
	my $result = [ map { s/\[[x\+]\]/\[X\]/; $_ }
					   grep { /(${PLAN_NAME_PREFIX}.+)/ }
						   split /\n/, $text
				   ];
	DEBUG "in get_votes for id $plan->{id}, author $plan->{author}, found votes?: ", (scalar @$result) ? 'yes' : 'no', ", result is: ", Dumper $result;
	
	return $result;
}

###----------------------------------------------------------------------

sub canonize_plan_name {
	my $name = shift;

	unless ( defined $name ) {
		warn "No name specified in canonize_plan_name" ;
		$name = '';
	}
	
	DEBUG "before, name is $name";

	$name =~ s/${PLAN_NAME_PREFIX}(?:\s*Plan\b\s*:?)?\s*//i;

	DEBUG "after, name is $name";

	return $name;
}

###----------------------------------------------------------------------

sub vote_type {
	my $vote = uc shift;

	DEBUG "in vote_type: vote is '$vote'";
	
	my ($type) = ($vote =~ /\[([+X-])\]/i);

	$type = 'X' if $type eq '+';
	
	DEBUG "vote type is: $type";
	
	return $type; #  Returns either 'X' or '-' for add to / remove from vote
}

###----------------------------------------------------------------------

sub tally_plans {
	my @posts = @_;

	DEBUG "entering tally_plans with N posts: ", scalar @posts;
	
	my $plan_votes = {};

	for my $post ( @posts ) {
		#    For each post, check to see if it has any votes.  If so, add
		#    this user's name to the list of voters.  If this is the first
		#    time we've see this plan, also add the name and the link

		my $votes = $post->{votes} || [];
		next unless @$votes;

		for my $v (@$votes) {
			#    People often slightly mistype the name of a plan --
			#    wrong caps, extra whitespace, whatever.  Try to
			#    prevent that.  Also, sometimes they do '[X] Plan foo'
			#    and sometimes they just do '[x] foo' so deal with
			#    that as well.
			#			
			my $key = lc canonize_plan_name($v);

			#    Explicitly strip non-ASCII because otherwise we can get
			#    things like different encodings for the ellipsis
			#    character (seen that) which cause two otherwise
			#    identical votes to not be registered as the same
			#
			$key =~ s/[^a-zA-Z0-9]//g;  

			DEBUG "Vote is: '$v'. Key is: '$key'";
			my $author = author_ref( $post->{author} );

			my ($type, $name) = (vote_type($v), canonize_plan_name($v));
			DEBUG "type is '$type'";
			
			if ( $type eq "-" ) { # Voting to be removed from that plan
				say STDERR "deleting cancelled vote for plan $key by voter $author";
				delete $plan_votes->{$key}{voters}{$author};
				if ( 0 == keys %{$plan_votes->{$key}{voters}} ) {
					delete $plan_votes->{$key};
				}
				next;
			}
			elsif ( ! exists $plan_votes->{$key} ) {
				$plan_votes->{$key} = {
					name   => $name,
					key    => $key,
					id     => $post->{id},
					author => $author,
					link   => $post->{link},
					voters => {},
				};
			}
			$plan_votes->{$key}{voters}{ $author }++;
		}		
	}

	DEBUG Dumper "leaving tally_votes.  plan votes: ", $plan_votes;
	
	return $plan_votes;
}

###----------------------------------------------------------------------

sub get_page {
	my $page_url = shift or	die "no page url specified in get_page()";

	say STDERR "getting page for $page_url";
	
	#    OSX 10.11 (El Capitan) ships with out-of-date SSL modules and
	#    no openssl headers, meaning that wget, Perl, python, and a
	#    few other things can't talk to https websites.  For whatever
	#    reason, curl works--maybe libssl and libcrypto were
	#    statically linked?  Anyway, I'm reduced to this hack.
	#
	`curl $page_url 2>/dev/null`;
}

###----------------------------------------------------------------------

sub format_plans {
	my $plans = shift;

	my $all_voters = {};
	DEBUG "Entering format_plans with plans: ", Dumper $plans;
	my $format_plan = sub {
		my $p = shift;

		my ($name, $voters, $link) = map { $p->{$_} } qw/name voters link/;
		my $num_voters = keys %$voters;
		
		DEBUG "Voters is: ", Dumper $voters;
		
		$all_voters->{$_}++ for keys %$voters; # Dedupe names for later use
		
		$name = canonize_plan_name($name);
		$voters = join(', ', sort { lc $a cmp lc $b } keys %$voters);
		DEBUG "Plan name is: '$name'";

		my $x = qq{
[B]Plan name: [URL=${link}]${name}[\/url][\/B]
Voters: ${voters}
Num votes:  ${num_voters}

};
	};

	my $result = "\[b\]CounterBot by eaglejarl, version $VERSION\[\/b\]\n\n";
	$result .= join('',
		 map { $format_plan->($_) }
			 #
			 #    Schwartzian transform in order to sort the plans by
			 #    number of voters and, within that, by plan name
			 #
			 map { $_->[1] } 
				 sort {
					 $b->[0] <=> $a->[0]                      # Number of voters
						 || $a->[1]{name} cmp $b->[1]{name}   # Plan name
					 }
					 map { [ scalar keys %{$_->{voters}}, $_ ] }
						 values %$plans
			 );
	DEBUG "all voters: ", Dumper $all_voters;
	my $count = scalar keys %$all_voters;
	$result .= "\n\nNumber of voters: $count";
	
	DEBUG "Leaving format_plans.";
	
	return $result;
}

###----------------------------------------------------------------------

sub output_report {
	#    This is really just here for future-proofing and to provide
	#    an easy hook for overriding -- if you want it to go somewhere
	#    else, just have your script do
	#    *Forum::SufficientVelocity::output_report = sub { ... }

	say shift();
}

###----------------------------------------------------------------------


1;

