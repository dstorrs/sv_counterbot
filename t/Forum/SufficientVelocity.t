#!/usr/bin/env perl

use strict;
use warnings;
use feature ':5.10';

use Data::Dumper;
use Test::More;
use Test::Exception;
use File::Slurp qw/slurp/;
use File::Spec;
use Cwd qw/abs_path/;
use File::Spec;
use File::Basename;

use lib "../../";
BEGIN {
  use_ok('Forum::SufficientVelocity', qw/:all/)
}



my $url = 'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-120';

###----------------------------------------------------------------------

throws_ok { init() } qr/Must specify a first page URL/, "Dies unless given first page URL";

is_deeply( init(first_url => $url),
	   {
	    first_url     => $url,
	    first_post_id => 0,
	    last_post_id => 0,
	    exclude_users => {},
	   },
	   "init works"
	 );


is( Forum::SufficientVelocity::cache_dir(),
    File::Spec->catfile( (File::Spec->splitpath( abs_path($0) ))[1], "cache"),
    "got correct cache dir");

isa_ok( make_root($url), 'HTML::TreeBuilder', 'make_root($url)' );

is_deeply(
	  [ get_page_urls_after( make_root($url) ) ],
	  [
	   'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-121',
	   'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-122',
	   'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-123',
	   'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-124',
	   'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-125',
	  ],
	  "Got correct urls for pages after 120"
	 );

{
  is( author_ref('foo'), '@foo',  'author_ref(foo)  eq "@foo"' );
  is( author_ref('@foo'), '@foo', 'author_ref(@foo) eq "@foo"' );
}

{
  is( get_id(make_root($url)), 2976, "id for first post on page 120 is 2976" );
  throws_ok { get_id() } qr/No post object \(HTML::Element based\) supplied in get_id\(\)/, "get_id() dies on no arg";
}

{
  throws_ok { get_posts() } qr/No page object \(HTML::Element derived\) specified in get_posts/,
    "get_posts() throws on no page object given";

  my @posts = grep { $_->isa('HTML::Element') } get_posts( make_root($url) );
  is( scalar @posts, 25, "Got correct number of HTML::Element's from get_posts" );
}


{
  throws_ok { remove_quote_blocks() } qr/No post object \(HTML::Element based\) supplied in remove_quote_blocks\(\)/,
    "remove_quote_blocks() dies on no arg";

  is( content_text( remove_quote_blocks( mock_post(1) ) ), quote_stripped_text(), "remove_quote_blocks works");
}


{
  my @li = make_root($url)->look_down(
				      _tag => 'li',
				      id => qr/post-\d+/
				     );
  my $post = $li[2];

  is_deeply(
	    make_plan($post),
	    {
	     post => $post,
	     link => 'https://forums.sufficientvelocity.com/posts/5894232/',
	     author => '@Sleeps Furiously',
	     id     => 2978,
	     text   => content_text( $post ),
	     votes  => [],
	    },
	    "make_plan is correct for post #2978 (no votes)"
	   );

  $post = $li[0];
  is_deeply(
	    make_plan($post),
	    {
	     post => $post,
	     link => 'https://forums.sufficientvelocity.com/posts/5894130/',
	     author => '@Sleeps Furiously',
	     id     => 2976,
	     text   => content_text( $post ),
	     votes  => [ ' [X] Superfund Me' ],
	    },
	    "make_plan is correct for post #2976"
	   );
}

{
  is( canonize_plan_name(), "", "canonize_plan_name()" );
  is( canonize_plan_name("foo"), "foo", "canonize_plan_name(foo)" );
  is( canonize_plan_name("Foo"), "Foo", "canonize_plan_name(Foo)" );
  is( canonize_plan_name("Planetary"), "Planetary", "canonize_plan_name(Planetary)" );


  subtest 'Various combinations of whitespace, vote type, and prefix' => sub {
    my $add_ws_around = sub { map { (" $_", $_, "$_ ", " $_ ") } @_	};
    for my $type ( $add_ws_around->('[x]', '[X]', '[-]') ) {
      for my $prefix ( $add_ws_around->('Plan ', 'Plan:', 'Action Plan:', 'Training Plan:') ) {
	is( canonize_plan_name("$type${prefix}Foobar"), "Foobar", "$type${prefix}Foobar" );
      }
    }
  };
}

{
  is( vote_type("[x] foo"), 'X', "Got right vote type for 'x'" );
  is( vote_type("[X] foo"), 'X', "Got right vote type for 'X'" );
  is( vote_type("[+] foo"), 'X', "Got right vote type for '+'" );
  is( vote_type("[-] foo"), '-', "Got right vote type for '-'" );
}

{
  my @posts = get_posts( make_root( $url ) );

  is_deeply( tally_plans(), {}, "tally_plans with no posts => empty {}" );
  is_deeply( tally_plans( map { make_plan($_) } @posts[0,9]),
	     {
	      'superfundme' => {
				'link' => 'https://forums.sufficientvelocity.com/posts/5894130/',
				'name' => 'Superfund Me',
				'author' => '@Sleeps Furiously',
				'id' => 2976,
				'voters' => {
					     'YES' => {
						       '@Sleeps Furiously' => 1
						      },
					     'NO' => {

						     },
					    },
				'key' => 'superfundme'
			       },
	     },
	     "got one-plan tally correctly"
	   );
  is_deeply( tally_plans( map { make_plan($_) } @posts),
	     {
	      'superfundme' => {
				'link' => 'https://forums.sufficientvelocity.com/posts/5894130/',
				'name' => 'Superfund Me',
				'author' => '@Sleeps Furiously',
				'id' => 2976,
				'voters' => {
					     'YES' => {
						       '@Sleeps Furiously' => 1,
						       '@Nighzmarquls' => 1,
						       '@GardenerBriareus' => 1,
						       '@Killer_Whale' => 1,
						      },
					     'NO' => {

						     },
					    },
				'key' => 'superfundme'
			       },
	      'begincontinuousoperations' => {
					      'link' => 'https://forums.sufficientvelocity.com/posts/5895541/',
					      'name' => 'Begin Continuous Operations',
					      'author' => '@Shark8',
					      'id' => 2987,
					      'voters' => {
							   'YES' => {
								     '@Shark8', => 1
								    },
							   'NO' => {

								   },
							  },
					      'key' => 'begincontinuousoperations'
					     },
	     },
	     "all plans tallied correctly"
	   )
}

done_testing();
exit;

###----------------------------------------------------------------------
###----------------------------------------------------------------------
###----------------------------------------------------------------------

###----------------------------------------------------------------------

sub mock_post {
  state $posts = [ get_posts( make_root( $url ) ) ];

  return $posts->[ shift() ];
}

sub quote_stripped_text {
  return
    q{Thanks, that helps.

Let's say that any sliver with Earthmover can move 250 ft^3 (5' x 5' x 10') per day. I'm not going to fuss with density of the material -- at this level of abstraction you dig the same amount through granite as through dirt.

It's as repaired as it's going to get. As a bonus, changing to a Mountain terrain type bumped the base defenses three levels. Anything trying to get close right now is seriously going to want to ask permission.

It's on the side of a ~4000m mountain, about a third of the way up. There's a wide and unpleasantly-sloped-but-still-hikable slope that leads up to it -- call it 1km wide and about 30 degrees. On the left and the right of that slope are cliffs that no sane person would want to climb. Loose rock, overhangs...very unpleasant.

Oh, good point. Yeah, let's say that every 2 points of Strike is 1 build action when used with Earthmover.};

}
