#!/usr/bin/env perl 

#perl2exe_include "HTML::TreeBuilder";
#perl2exe_include "Forum::SufficientVelocity";
#perl2exe_include "Data::Dumper";

use warnings;
use strict;
use feature ':5.10';
use HTML::TreeBuilder 5 -weak;
use Data::Dumper;
use Getopt::Long;
use lib '.';

use Forum::SufficientVelocity;

use constant BASE_URL => 'https://forums.sufficientvelocity.com/';

#    Search '=head1' for docs

#---------- Get all necessary command values 

my ($first_post_id, $first_url, $GMs, $stop, $debug) = get_cli_options();
our $DEBUG = $debug || 0;

#    Set some defaults
if ( ! @$GMs ) {
	no warnings 'experimental::smartmatch';  # 'when' will warn even if there's no ~~ involved

	for ($first_url) {
		when (/slivers-in-the-chaos-lands/) { @$GMs = qw/eaglejarl/ }
		when (/marked-for-death/)           { @$GMs = qw/eaglejarl Jackercracks
														 AugSphere Velorien/; }
		default {}
	}
}
$stop ||= 0;

$first_url = BASE_URL . $first_url  unless $first_url =~ /^https?:/;

init(
	first_url       => $first_url,
	first_post_id   => $first_post_id,
	exclude_users   => $GMs,
	stop_id         => $stop,
);

generate_report();

exit(0);

###----------------------------------------------------------------------
###----------------------------------------------------------------------
###----------------------------------------------------------------------

sub get_cli_options {
	my ($first_post_id, $first_url, $GMs, $temp, $stop, $debug) = (0);
	
	GetOptions("page|start|p|s=s"   => \$first_url,         # string
			   "first_post|id=i"    => \$first_post_id,      # integer
			   "gm=s@"              => \$temp,
			   "stop=i"             => \$stop,
			   "debug"              => \$debug,
		   )  or die("Error in command line arguments\n");

	#  Support both: '--gm bob --gm tom'  and '--gm bob,tom'
	@$GMs = split(',', join(',', @{ $temp || []}));

	check_usage( $first_url, $first_post_id, $GMs, $stop );
	
	return ($first_post_id, $first_url, $GMs, $stop, $debug);
}

###----------------------------------------------------------------------

sub check_usage {
	my ( $start_page, $first_post_id, $GMs, $stop ) = @_;

	die "No start page specified. Use '--start <URL>'\n" unless $start_page;
	die "First post ID cannot be negative"    unless $first_post_id >= 0;
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
