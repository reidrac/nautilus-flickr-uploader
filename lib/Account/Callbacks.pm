#
# nautilus-flickr-uploader - upload pics to Flickr from Nautilus
# Copyright (C) 2009, 2010  Juan J. Martinez <jjm@usebox.net>
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
	my $api = Flickr::API->new( $main::api );

	if( !$step )
	{
		my $response = $api->execute_method('flickr.auth.getFrob');
		$frob = $response->{tree}{children}[1]{children}[0]{content};
		my $url = $api->request_auth_url('write', $frob);

		# I believe this system usage is safe (AFAIK no shell involved)
		system( 'xdg-open', $url );

		$step++;

		my $titleLabel = $gladexml->get_widget( 'TitleLabel' );
		$titleLabel->set_markup( _( '<b>Return to this window after you'
		.' have finished the authorization process on Flickr.com</b>' ) );

		my $mainTextLabel = $gladexml->get_widget( 'MainTextLabel' );
		$mainTextLabel->set_markup( _( 'Once you\'re done, please click the'
		.' <i>Finish</i> button on this dialog.' ) );

		my $tipLabel = $gladexml->get_widget( 'TipLabel' );
		$tipLabel->set_markup( _( '<small>You can revoke this authorization'
		.' at any time in you account page on Flickr.com.</small>' ) );

		# TODO: add the mnemonic?
		my $nextButton = $gladexml->get_widget( 'NextButton' );
		$nextButton->set_label( _( 'Finish' ) );
	}
	else
	{
		my $response = $api->execute_method('flickr.auth.getToken', {'frob' => $frob});
		$main::config->{'token'} = $response->{tree}{children}[1]{children}[1]{children}[0]{content};
		$main::config->{'username'} = $response->{tree}{children}[1]{children}[5]{attributes}{username};

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
