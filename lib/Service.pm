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
package Service;

use Net::DBus::Exporter qw(net.usebox.nautilusFlickrUploader.remote);

use base qw(Net::DBus::Object);

dbus_method("add", ["string"], ["bool"]);

sub new
{
    my $class = shift;
    my $service = shift;
    my $self = $class->SUPER::new($service, "/net/usebox/nautilusFlickrUploader");

    bless $self, $class;

    return $self;
}

sub add
{
    my $self = shift;
    my $files = shift;

    if( $Upload::busy )
    {
        return 0;
    }

    my @files = split( '\*', $files );

    @Upload::FILES = Upload::ExpandDirectories( @files );

    my $progressBar = $Upload::gladexml->get_widget( 'ProgressBar' );
    $progressBar->show( );

    Glib::Idle->add( \&Upload::LoadPhotos, $#Upload::FILES );

    my $window = $Upload::gladexml->get_widget( 'UploadDialog' );
    $window->set_urgency_hint( 1 );

    return 1;
}

1 ;
