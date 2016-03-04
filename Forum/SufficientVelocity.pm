package Forum::SufficientVelocity;

use strict;
use warnings;
use feature ':5.10';

use Data::Dumper;
use HTML::Element;
use Log::Log4perl qw(:easy);
use HTML::TreeBuilder 5 -weak;

use constant VERBOSE => 0;
use constant BASE_URL => 'https://forums.sufficientvelocity.com/';

Log::Log4perl->easy_init($ERROR);  # use $DEBUG or $ERROR


our (@ISA, @EXPORT_OK);
BEGIN {
	require Exporter;
	@ISA = qw(Exporter);
	our @EXPORT_OK   = qw/get_page
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
	our %EXPORT_TAGS = (all => [ qw/get_page
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

my $PLAN_NAME_PREFIX = qr/^\s*\[[X-]\]\s*/i;

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
	sub url           { _get_data('url')           }
	
	sub init {
		#    I could make this into an OO constructor, but OO is overkill
		#    for what we need.  In the future, if I were going to expand
		#    this to cover other forum boards with slightly different
		#    codebases, it *might* make sense to go OO and have the
		#    differences be defined as subclasses.  For now, though, a
		#    simple 'init' is fine.
		
		my %args = @_;

		#    Options:
		# url            => 'http...',
		# first_post_id  => 2,
		# exclude_users  => [ qw/bob tom sue/ ], #  Will be converted to qw/@bob @tom @sue/ if it isn't already

		
		die "Must specify a first page URL using: url => 'http...'" unless $args{url} && $args{url} =~ /^\s*http/;
		$args{url} =~ s/^\s*//;
		$args{url} =~ s/\s*$//;
		
		$args{first_post_id} ||= 0;
		
		$args{ exclude_users } ||= [];

		#    usernames should start with '@', but only one '@'.  Turn
		#    the array ref into a hash ref for easy reference
		#
		my @names = @{ $args{ exclude_users } };
		$args{ exclude_users } = {
			{ map { /^@/ ? $_ : '@' . $_ => 1 } @names },
		};
		
		$data = \%args;
	}
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

	my $navlinks = $root->look_down(
		_tag => 'div',
		class => 'PageNav'
	);

	my ($base_url, $sentinel, $last_page, $current_page) = 
		map { chomp; $_ }
			map { $navlinks->attr($_) }
				qw/data-baseurl data-sentinel data-last data-page/;

	$base_url =~ s/$sentinel//;
	$base_url = 'https://forums.sufficientvelocity.com/' . $base_url;
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
	
	my $text = $p->look_down(_tag => 'div', class => 'publicControls')->look_down(_tag => '~text')->attr('text');
	
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
		DEBUG "ID is $id, first is first_post_id().  Skipping.";
		return;
	}
	
	remove_quote_blocks($post);  # Ignore text that was quoted from an earlier post

	#    Retrieve the link to the post
	my $link = $post->look_down(_tag => 'a', href => qr<posts/\d+/>)->attr('href');
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
	#	delete $plan->{post}; say Dumper $plan; $plan->{post} = $post; #  FOR DEBUGGING

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
	#    front of every open tag and behind ever close tag.  So, after
	#    you remove the tags something that SHOULD be this:
	#        [X] Plan do all the things
	#    is actually this:
	#        [X] Plan 
	#           do all the
	#        things
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
	
	$text =~ s/ //g;
	$text =~ s/^\s*//;
	$text =~ s/\s*$//;

	return $text;
}

###----------------------------------------------------------------------

sub get_posts {
	my $page = shift or die "No page object (HTML::Element derived) specified in get_posts"; 
	$page->look_down(
		_tag => 'li',
		id => qr/post-\d+/
	);
}

###----------------------------------------------------------------------

sub get_votes {
	my $plan = shift || die "No post specified in get_votes";
	my $text = $plan->{text};

	#    Votes can now have either '[X]' or '[-]' and '[x]' will be forcibly
	#    uppercased.  '[-]' means 'remove me from this plan'
	#

	DEBUG "in get_votes, text is: $text";
	my $result = [ map { s/\[x\]/\[X\]/; $_ }
					   grep { /(${PLAN_NAME_PREFIX}.+)/ }
						   split /\n/, $text
				   ];
	DEBUG "in get_votes, result is: ", Dumper $result;
	
	return $result;
}

###----------------------------------------------------------------------

sub canonize_plan_name {
	my $name = shift;

	DEBUG "before, name is $name";

	$name =~ s/${PLAN_NAME_PREFIX}(?:\s*Plan\b\s*:?)?\s*//i;

	DEBUG "after, name is $name";

	return $name;
}

###----------------------------------------------------------------------

sub vote_type {
	my $vote = uc shift;

	DEBUG "in vote_type: vote is '$vote'";
	
	my ($type) = ($vote =~ /\[([X-])\]/i);

	DEBUG "vote type is: $type";
	
	return $type; #  Returns either 'X' or '-' for add to / remove from vote
}

###----------------------------------------------------------------------

sub tally_plans {
	my @posts = @_;

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
			$key =~ s/\W//g;

			DEBUG "Vote is: '$v'. Key is: '$key'";
			my $author = author_ref( $post->{author} );

			my ($type, $name) = (vote_type($v), canonize_plan_name($v));
			#			say "type is '$type'";
			
			if ( $type eq "-" ) { # Voting to be removed from that plan
				say "deleting for plan $key, author $author";
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

	#DEBUG Dumper "plan votes: ", $plan_votes;
	
	return $plan_votes;
}

1;

