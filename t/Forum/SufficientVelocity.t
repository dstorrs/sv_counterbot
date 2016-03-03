#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Slurp qw/slurp/;
use File::Spec;
use Cwd;
use feature ':5.10';


use lib "../../";
BEGIN { use_ok('Forum::SufficientVelocity', qw/:all/) }


#    Mock the network-contacting elements of F::SV
no warnings;
local *Forum::SufficientVelocity::get_page = \&mock_get_page;
use warnings;

my $url = 'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-13';

###----------------------------------------------------------------------

throws_ok { init() } qr/Must specify a first page URL/, "Dies unless given first page URL";

is_deeply( init(url => $url),
		   {
			   url           => $url,
			   first_post_id => 0,
			   exclude_users => {},
		   },
		   "init works"
	   );


{
 	my $text = slurp _make_path( $url );
 	is( get_page($url), $text, "correctly got page 13" );
};

isa_ok( make_root($url), 'HTML::TreeBuilder', 'make_root($url)' );

is_deeply(
	[ get_page_urls_after( make_root($url) ) ],
	[
		'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-14',
		'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-15',
		'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-16',
		'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-17',
		'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-18',
		'https://forums.sufficientvelocity.com/threads/slivers-in-the-chaos-lands-mtg-multicross.26697/page-19',
	],
	"Got correct urls for pages after 13"
);

{
	is( author_ref('foo'), '@foo',  'author_ref(foo)  eq "@foo"' );
	is( author_ref('@foo'), '@foo', 'author_ref(@foo) eq "@foo"' );
}

{
	is( get_id(make_root($url)), 301, "id is 301" );	
	throws_ok { get_id() } qr/No post object \(HTML::Element based\) supplied in get_id\(\)/, "get_id() dies on no arg";
}

{
	throws_ok { get_posts() } qr/No page object \(HTML::Element derived\) specified in get_posts/,
		"get_posts() throws on no page object given";

	my @posts = grep { $_->isa('HTML::Element') } get_posts( make_root($url) );
	is( scalar @posts, 25, "Got correct number of HTML::Element's from get_posts" );
}

isa_ok( mock_post(0), 'HTML::Element', "mock_post(0) works" );

{
	
	is( 
		text_of( mock_post(0) ),
		" frommermanLocation:US Additional benefit if hive spawning: An unknown chance that the plains infested with Orks shifts away. Could also happen to the forest near the elves, but I don't think (?) we Manabonded near their base.   frommerman, Feb 28, 2016 at 4:21 AM #301",
		"text_of() correct on first post"
	);
	throws_ok { content_text() } qr/No post object \(HTML::Element derived\) specified in content_text\(\)/,
		"context_text throws when no post given"; 
	is(
		content_text( mock_post(0) ),
		"Additional benefit if hive spawning: An unknown chance that the plains infested with Orks shifts away. Could also happen to the forest near the elves, but I don't think (?) we Manabonded near their base.",
		"content_text() correct on first post"
	);
	
}

		
 
{
	throws_ok { remove_quote_blocks() } qr/No post object \(HTML::Element based\) supplied in remove_quote_blocks\(\)/,
		"remove_quote_blocks() dies on no arg";
	
	is( content_text( remove_quote_blocks( mock_post(1) ) ), quote_stripped_text(), "remove_quote_blocks works");
}


TODO: {
	my @li = make_root($url)->look_down(
		_tag => 'li',
		id => qr/post-\d+/
	);
	my $post = $li[0];
	
	is_deeply(
		make_plan($post),
		{
			post => $post,
			link => 'https://forums.sufficientvelocity.com/posts/5506935/',
			author => '@frommerman',
			id     => 301,
			text   => content_text( $post ),
			votes  => [],
		},
		"make_plan is correct for post #301 (no votes)"
	);

	$post = $li[14];
	is_deeply(
		make_plan($post),
		{
			post => $post,
			link => 'https://forums.sufficientvelocity.com/posts/5509401/',
			author => '@frommerman',
			id     => 315,
			text   => content_text( $post ),
			votes  => [ '[X] Plan Bracing for Waaaaugh' ],
		},
		"make_plan is correct for post #315"
	);	
}


done_testing();
exit;

###----------------------------------------------------------------------
###----------------------------------------------------------------------
###----------------------------------------------------------------------

sub _make_path {
	my $url = shift;
	
	$url =~ s{^https://forums.sufficientvelocity.com/threads/}{};
	$url =~ s{/}{-}g;

	my (undef, $dirs, $file) = File::Spec->splitpath( File::Spec->rel2abs( __FILE__ ) );
	return File::Spec->catfile( $dirs, 'data', 'slivers-in-the-chaos-lands-mtg-multicross.26697-page-13' );
}

# ###----------------------------------------------------------------------

sub mock_get_page {
	my $url = shift;
	return scalar slurp _make_path( $url );
}
	
###----------------------------------------------------------------------

sub mock_post {
	state $posts = [ get_posts( make_root( $url ) ) ];
	
	return $posts->[ shift() ];
}

sub quote_stripped_text {
	return
"Huh, can we get a map? We need to find a place that's not A) Elf Territory, B) Orc Territory, or C) Super Predator Territory.

I don't think it's quite that easy - they can only adjust reality, not completely defy it. Which means they need resources of some sort. And only certain Orks are capable of making certain techs, which means that if they only have a limited number, they won't be able to make much. I'd say these are probably fantasy orcs regardless because they don't seem to have any gear whatsoever.";

}
