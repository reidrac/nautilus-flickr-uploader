#
# nautilus-flickr-uploader - upload pics to Flickr from Nautilus
# Copyright (C) 2009-2012  Juan J. Martinez <jjm@usebox.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Account::Callbacks;

use strict;
use warnings;

use vars qw( $gladexml );

use YAML 'DumpFile';

my $frob;
my $step = 0;
my $req_token;
my $req_token_secret;

sub Init
{
	$gladexml = $Account::gladexml;
}

sub on_AccountDialog_close
{
	if( !$Upload::gladexml )
	{
		Gtk2->main_quit;
	}
	else
	{
		my $dialog = $gladexml->get_widget( 'AccountDialog' );
		$dialog->destroy( );
		$Account::gladexml = undef;
	}
}

sub on_NextButton_clicked
{
	my $conf = $main::config;
    my $ua = LWP::UserAgent->new;

	if( !$step )
	{
        my $request = Net::OAuth->request( 'request token' )->new(
            consumer_key => $main::api->{'key'},
            consumer_secret => $main::api->{'secret'},
            request_url => 'http://www.flickr.com/services/oauth/request_token',
            request_method => 'GET',
            signature_method => 'HMAC-SHA1',
            timestamp => time(),
            nonce => 'rtk' .time(),
            callback => 'oob',
            );

        $request->sign;

        my $response = $ua->get($request->to_url);

        if( !$response->is_success ) {
            my $mainTextLabel = $gladexml->get_widget( 'MainTextLabel' );
            $mainTextLabel->set_markup( _( "Flickr API it's not available"
                ." at the moment: error " .$response->code ) );
            $step = 0;
            die "Flickr API it's not available: error " .$response->code;
        }

        $response = Net::OAuth->response( 'request token' )->from_post_body( $response->content );
		$req_token = $response->token;
		$req_token_secret = $response->token_secret;

		my $url = "http://www.flickr.com/services/oauth/authorize?oauth_token="
                  .$response->token ."&perms=write";

		# I believe this system usage is safe (AFAIK no shell involved)
		system( 'xdg-open', $url );

		$step++;

		my $titleLabel = $gladexml->get_widget( 'TitleLabel' );
		$titleLabel->set_markup( _( '<b>Return to this window after you'
		.' have finished the authorization process on Flickr.com</b>' ) );

		my $mainTextLabel = $gladexml->get_widget( 'MainTextLabel' );
		$mainTextLabel->set_markup( _( 'Once you\'re done, please enter the'
        .' verification code and click the <i>Finish</i> button on this dialog.' ) );

		my $tipLabel = $gladexml->get_widget( 'TipLabel' );
		$tipLabel->set_markup( _( '<small>You can revoke this authorization'
		.' at any time in you account page on Flickr.com.</small>' ) );

		# TODO: add the mnemonic?
		my $nextButton = $gladexml->get_widget( 'NextButton' );
		$nextButton->set_label( _( 'Finish' ) );

		my $verifiedLabel = $gladexml->get_widget( 'VerifiedLabel' );
        $verifiedLabel->set_sensitive( 1 );

		my $verifiedEntry = $gladexml->get_widget( 'VerifiedEntry' );
        $verifiedEntry->set_sensitive( 1 );
	}
	else
	{
		my $verifiedEntry = $gladexml->get_widget( 'VerifiedEntry' );
        my $verified = $verifiedEntry->get_text( );

        if( !$verified ) {
            warn "Warning: No verification code";
            return;
        }

        my $request = Net::OAuth->request( 'access token' )->new(
            consumer_key => $main::api->{'key'},
            consumer_secret => $main::api->{'secret'},
            token => $req_token,
            token_secret => $req_token_secret,
            request_url => 'http://www.flickr.com/services/oauth/access_token',
            request_method => 'GET',
            signature_method => 'HMAC-SHA1',
            timestamp => time(),
            nonce => 'atk' .time(),
            verifier => $verified,
            );

        $request->sign;

        my $response = $ua->get($request->to_url);
        $response = Net::OAuth->response( 'access token' )->from_post_body( $response->content );
		$main::config->{'token'} = $response->token;
		$main::config->{'token_secret'} = $response->token_secret;
		$main::config->{'username'} = $response->username;

		DumpFile( $main::config_file,  \%$conf ) or
			warn 'Warning: failed to write de configuration';

		my $dialog = $gladexml->get_widget( 'AccountDialog' );
		$dialog->destroy( );
		$Account::gladexml = undef;

		# start over
		$step = 0;

		if( !$Upload::gladexml )
		{
			Upload::Init( );
		}
		Glib::Idle->add( \&Upload::TestAccount );
	}
}

1 ; 
