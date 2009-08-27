#
# nautilus-flickr-uploader - upload pics to Flickr from Nautilus
# Copyright (C) 2009  Juan J. Martinez <jjm@usebox.net>
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
package Upload::Callbacks;

use strict;
use warnings;

use vars qw( $gladexml );

use Gtk2::Gdk::Keysyms;
use YAML 'DumpFile';

sub Init
{
	$gladexml = $Upload::gladexml;
}

sub on_UploadDialog_close
{
	Gtk2->main_quit;

	# get current configuration from the GUI and store it in a file
	my $conf = $main::config;

	$conf->{'privacy'} = 'public';
	my $radio = $gladexml->get_widget( 'RadioFriends' );
	if( $radio->get_active( ) )
	{
		$conf->{'privacy'} = 'friends';
	}
	$radio = $gladexml->get_widget( 'RadioFamily' );
	if( $radio->get_active( ) )
	{
		$conf->{'privacy'} = 'family';
	}

	my $spin = $gladexml->get_widget( 'SizeSpinButton' );
	$conf->{'size'} = scalar( $spin->get_value( ) );

	$conf->{'resize'} = 'no';
	my $resize = $gladexml->get_widget( 'ResizeCheckButton' );
	if( $resize->get_active( ) )
	{
		$conf->{'resize'} = 'yes';
	}

	DumpFile( $main::config_file,  \%$conf ) or
		warn 'Warning: failed to write de configuration';
}

sub on_ResizeCheckButton_toggled
{
	my $check = $gladexml->get_widget( 'ResizeCheckButton' );
	my $spin = $gladexml->get_widget( 'SizeSpinButton' );
	my $pixels = $gladexml->get_widget( 'PixelsLabel' );

	$spin->set_sensitive( $check->get_active );
	$pixels->set_sensitive( $check->get_active );
}

sub on_PhotoView_key_release_event
{
	my ( $widget, $event ) = @_;

	if( $event->keyval == $Gtk2::Gdk::Keysyms{Delete} )
	{
		my $list = $gladexml->get_widget( 'PhotoView' );

		my @selected = $list->get_selected_indices( );
		if( scalar( @selected ) )
		{
			splice( @{$list->{data}}, $selected[0], 1 );
		}
	}
}

sub on_ChangeUserButton_clicked
{
	if( !$Account::gladexml )
	{
		Account::Init( );
	}
}

sub on_OkButton_clicked
{
	my $list = $gladexml->get_widget( 'PhotoView' );

	if( !scalar( $list->{data} ) )
	{
		on_UploadDialog_close( );
		return;
	}

	my $ok = $gladexml->get_widget( 'OkButton' );
	$ok->set_sensitive( 0 );

	my $progressBar = $gladexml->get_widget( 'ProgressBar' );
	$progressBar->show( );

	Glib::Idle->add( \&Upload::UploadFiles, $#{$list->{data}} );
}

1 ; 
