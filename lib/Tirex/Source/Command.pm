#-----------------------------------------------------------------------------
#
#  Tirex/Source/Command.pm
#
#-----------------------------------------------------------------------------

use strict;
use warnings;

use Carp;

use IO::Socket;

#-----------------------------------------------------------------------------
package Tirex::Source::Command;
use base qw( Tirex::Source );

=head1 NAME

Tirex::Source -- A source of a job request

=head1 SYNOPSIS

 my $source = Tirex::Source::Command->new();
 $source->notify();

=head1 DESCRIPTION

Source using Tirex messages sent through UDP.

=head1 METHODS

=head2 Tirex::Source::Command->new( socket => $socket )

Create source object for UDP connection.

=cut

sub new
{
    my $class = shift;
    my %args  = @_;

    my $self = bless \%args => $class;

    return $self;
}

sub readable
{
    my $self = shift;
    my $sock = shift;

    my $buf;
    my $peer = $sock->recv($buf, $Tirex::MAX_PACKET_SIZE);
    my $args = Tirex::parse_msg($buf);

    foreach (keys %$args) { $self->{$_} = $args->{$_}; };

    return &Tirex::Source::STATUS_MESSAGE_COMPLETE;
}

sub get_msg_type
{
    my $self = shift;
    return $self->{'type'};
}

sub make_job
{
    my $self = shift;

    my $metatile = eval {
        my $mt = Tirex::Metatile->new(
            map   => $self->{'map'}, 
            level => $self->{'level'},
            x     => $self->{'x'}, 
            y     => $self->{'y'}, 
            z     => $self->{'z'}
        );
        Tirex::Map->get_map_for_metatile($mt);
        return $mt;
    };

    # if we couldn't create the metatile...
    if ($@)
    {
        ::syslog('warning', $@) if ($Tirex::DEBUG);
        # and the client wanted an answer...
        if (defined $self->{'id'})
        {
            # send error message
            $self->reply({
                type    => $self->{'type'},
                map     => $self->{'map'}, 
                level   => $self->{'level'}, 
                x       => $self->{'x'}, 
                y       => $self->{'y'}, 
                z       => $self->{'z'},
                prio    => $self->{'prio'},
                result  => 'error_illegal_metatile'
            });
        }
        return;
    }

    my $job = eval {
        Tirex::Job->new( metatile => $metatile, prio => $self->{'prio'} );
    };

    # if we couldn't create the job...
    if ($@)
    {
        # and the client wanted an answer...
        if (defined $self->{'id'})
        {
            # send error message
            $self->reply({
                type    => $self->{'type'},
                map     => $self->{'map'}, 
                level   => $self->{'level'}, 
                x       => $self->{'x'}, 
                y       => $self->{'y'}, 
                z       => $self->{'z'},
                prio    => $self->{'prio'},
                result  => 'error_illegal_prio'
            });
        }
        return undef;
    }

    $job->add_notify($self) if (defined $self->{id});
    return $job;
}


=head2 $source->notify($job)

Send notify that a tile was rendered back to source.

=cut

sub notify
{
    my $self = shift;
    my $job  = shift;

    my $msg = $job->to_msg( type => 'metatile_enqueue_request', id => $self->{'id'}, result => $job->{'success'} ? 'ok' : 'error' );

    return $self->reply($msg);
}

=head2 $source->reply($msg)

Send a reply message to this source. The id is automatically filled in. The parameter
is a hash with the message.

Returns the result of the sockets send method.

=cut

sub reply
{
    my $self = shift;
    my $msg  = shift;

    $msg->{'id'} = $self->{'id'} if (defined $self->{'id'});

    return $self->{'socket'}->send( Tirex::create_msg($msg) );
}

sub name
{
    return 'C';
}

#-----------------------------------------------------------------------------

1;


#-- THE END ------------------------------------------------------------------
