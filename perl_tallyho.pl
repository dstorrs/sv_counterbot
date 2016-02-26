#!/usr/bin/env perl 


use warnings;
use strict;
use feature ':5.10';
use HTML::TreeBuilder 5 -weak;
use Data::Dumper;
use GetOpt::Long;
use Log::Log4perl qw(:easy);
use constant VERBOSE => 0;

my $VERSION  = 0.9;


#
#    Search '=head1' for docs
#

Log::Log4perl->easy_init($ERROR);  # Or $ERROR when not debugging


#----------
my $base_url = 'https://forums.sufficientvelocity.com/';
my $PLAN_NAME_PREFIX = qr/^\s*\[[X-]\]\s*/i;

my $default_page = 'threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-5';

my $first_page = shift || $default_page;
$first_page = "$base_url$first_page"  unless $first_page =~ /^https?:/;

#  Set this to, e.g. 1401 in order to skip posts #1-1400 
my $FIRST_POST_ID = 104;


my @GMs;
given ($first_page) {
	when (/slivers-in-the-chaos-lands/) { @GMs = qw/@eaglejarl/ }
	when (/marked-for-death/)           { @GMs = qw/@eaglejarl @Jackercracks
													@AugSphere @Velorien/; }
	default {}
}
my %EXCLUDE_USERS = map { $_ => 1 } @GMs;

# %EXCLUDE_USERS = ();  # FOR DEBUGGING, IF YOU DON'T WANT TO SKIP GM POSTS

#----------


my $root = make_root( $first_page );

my @page_urls = get_page_urls_after( $root );

my $output =
	format_plans( 
		tally_plans(
 			map { make_plan($_) }
				map {
					$_->look_down(
						_tag => 'li',
						id => qr/post-\d+/
					)
				}
					$root, map { make_root($_) } @page_urls
			)
	);

say "Mac CounterBot (\@eaglejarl), version $VERSION\n";

say $output;

exit(0);

###----------------------------------------------------------------------
###----------------------------------------------------------------------
###----------------------------------------------------------------------

sub make_plan {
	my $post = shift || die "no post object specified";

	my $author = author_ref( $post->attr('data-author') );
	my $id = get_id( $post );

	DEBUG  "author, id: '$author', '$id'";

	return if $EXCLUDE_USERS{ $author };
	if ( $id < $FIRST_POST_ID ) {
		DEBUG "ID is $id, first is $FIRST_POST_ID.  Skipping.";
		return;
	}
	
	remove_quote_blocks($post);
	
	my $link = $post->look_down(_tag => 'a', href => qr<posts/\d+/>)->attr('href');
	unless ( $link =~ /^http/ ) {
		$link = $base_url . $link;
	}
	DEBUG "link is $link";
	
	my $plan = {
		post   => $post,
		author => $author,
		link   => $link,
		id     => $id,
		text   => text_of(
			$post->look_down(
				_tag => 'div',
				class => 'messageContent'
			)
		),
	};
	
	#    Add the votes after creating the post so that we only have to
	#    do text_of once.
	$plan->{votes} = get_votes( $plan );
	#	delete $plan->{post}; say Dumper $plan; $plan->{post} = $post; #  FOR DEBUGGING

	return $plan;
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

sub canonize_plan_name {
	my $name = shift;

	DEBUG "before, name is $name";

	$name =~ s/${PLAN_NAME_PREFIX}(?:\s*Plan\s*:?)?\s*//i;

	DEBUG "after, name is $name";

	return $name;
}

###----------------------------------------------------------------------

sub format_plans {
	my $plans = shift;

	DEBUG "Entering format_plans...";
	my $format_plan = sub {
		my $p = shift;

		my ($name, $voters, $link) = map { $p->{$_} } qw/name voters link/;
		my $num_voters = keys %$voters;

		$name = canonize_plan_name($name);
		$voters = join(', ', sort { lc $a cmp lc $b } keys %$voters);
		DEBUG "Plan name is: '$name'";
		
		my $x = qq{
[B]Plan name: [URL=${link}]${name}[\/url][\/B]
Voters: ${voters}
Num votes:  ${num_voters}
};
	};

	my $result = join('',
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

	DEBUG "Leaving format_plans.";
	return $result;
}

###----------------------------------------------------------------------

sub author_ref {
	my $author = shift || die "no author specified in 'author_ref'";

	return $author if $author =~ /^@/;
	return '@' . $author;
}

###----------------------------------------------------------------------

sub make_root {  
	my $url = shift;
	my $root = HTML::TreeBuilder->new_from_content( get_page($url) );
	$root->objectify_text;
	return $root;
}

###----------------------------------------------------------------------

sub tally_plans {
	my @posts = @_;

	my $plan_votes = {};

	for my $post ( @posts ) {
		#    For each post, check to see if it has any votes.  If so, add
		#    this user's name to the list of voters.  If this is the first
		#    time we've see this plan, also add the name and the link

		my $votes = $post->{votes};
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

	#	say Dumper "plan votes: ", $plan_votes;
	
	return $plan_votes;
}

###----------------------------------------------------------------------

sub get_id {
	my $p = shift ||  die "no post specified in get_id";
	
	my $text = $p->look_down(_tag => 'div', class => 'publicControls')->look_down(_tag => '~text')->attr('text');
	
	my ($id) =  $text =~ /(\d+)/;  #  Cut off the leading '#'
	return $id;
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

sub remove_quote_blocks {
	my $post = shift || die "No post specified in remove_quote_blocks";
	$_->delete for $post->look_down(
		_tag => 'div',
		class => qr/\bbbCodeQuote\b/,
	);
	return $post;
}

###----------------------------------------------------------------------

sub get_page {
	my $page_url = shift or	die "no page url specified in get_page()";

	say STDERR "getting page for $page_url";
	
	#    OSX 10.11 (El Capitan) ships with out-of-date SSL modules,
	#    meaning that wget, Perl, python, and a few other things can't
	#    talk to https websites.  For whatever reason, curl
	#    works--maybe libssl and libcrypto were statically linked?
	#    Anyway, I'm reduced to this hack.
	#
	`curl $page_url 2>/dev/null`;
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

__END__

=head1 NAME

CounterBot

=head1 SYNOPSIS

Counts up votes in a quest on SufficientVelocity.  Uses approval
voting, so questers can vote for multiple plans.

=head1 DESCRIPTION

Reads through from the specified page (or post) to the last page in
the thread, compiles a list of all votes, and then spits out a report
at the end summarizing who voted for what.  A typical report might be:

    Mac CounterBot (@eaglejarl), version 0.9


    [B]Plan name: [URL=https://forums.sufficientvelocity.com/posts/5468116/]Arrival  [/url][/B]
    Voters: @AZATHOTHoth, @Citrus, @FullNothingness, @godofbiscuit, @Jackercracks, @Kingspace, @Sigil, @tarrangar, @TempestK, @TheEyes, @Void Stalker
    Num votes:  11
    
    [B]Plan name: [URL=https://forums.sufficientvelocity.com/posts/5469924/]Arrival + Wands[/url][/B]
    Voters: @Angle, @DonLyn, @FullNothingness, @HyperCatnip, @Jackercracks, @Radvic, @rangerscience, @RedV, @Solace
    Num votes:  9
    
    [B]Plan name: [URL=https://forums.sufficientvelocity.com/posts/5469924/]Arrival + Wands + Survivors[/url][/B]
    Voters: @Angle, @Jack Stargazer, @Jackercracks, @rangerscience, @TheEyes
    Num votes:  5
    
    ...etc...

The various plans are linked back to where they were defined and
everyone who voted is given an alert so that they know the results are
up and can confirm their votes if they like.[1]

Note that this is *approval voting*.  In the report above,
@Jackercracks voted for three separate plans so he's listed on all
those plans.  That's a feature, not a bug.


=head1 USE ON OTHER SITES

CounterBot will probably work on any other board written on the
same codebase as SV -- SpaceBattles and Questionable Questing should
be fine, although that hasn't been tested.


=head1  EDGE CASES 

Once in a while you'll see this:

 - Al writes post #2
 - Bob writes post #3 with the "[X] Do FOO" voting plan
 - Al goes back and edits post #2 to contain a vote for "Do FOO".

In this case the plan will be linked to post #2, since that was where
CounterBot first saw the plan referenced.  

=head1  TODO

- Support voting by username.

- Okay, looks like we need to deal with the item listed under Edge
  Case where someone edits their post to vote for a later-proposed
  plan so the link to the plan is wrong.

- The various control variables should be moved into CLI options.

- A config file should be established so that standard variables
  (e.g. GM names) don't need to be entered each time.  Could replace
  CLI options entirely, although it's still good to have those for
  convenience.

- Cache pages in a subfolder so that we don't need to retrieve them
  every time.

- Maybe add a 'stop at page X' switch?  There is one in SV's Tallybot,
  although I'm not sure what it's for.  It would simplify debugging by
  letting you reduce the number of pages to retrieve.  Otherwise it
  seems like it would only be good for re-counting old votes.

- Yell at SV for their wonky markup.

- Yell at Apple for their never-sufficient-bedamned antique crypto
  libraries that mean I have to use backticks instead of a proper LWP
  call.

=cut
