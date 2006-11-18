package Combust::Control::Bitcard;
use strict;
use Apache::Constants qw(OK);
use Authen::Bitcard;
use Carp qw(cluck);

#use base qw(Class::Accessor::Fast);
#__PACKAGE__->mk_accessors(qw(info_required info_optional));

our $cookie_name = 'bc_u';

sub bc_check_login_parameters {
    my $self = shift;
    if ($self->req_param('sig') or $self->req_param('bc_id')) {
        my $bc = $self->bitcard;
        my $bc_user = eval { $bc->verify($self->r) };
        warn $@ if $@;
        unless ($bc_user) {
            warn "Authen::Bitcard error: ", $bc->errstr;
        }
        if ($bc_user and $bc_user->{id}) {
            my $user;
            if ($self->bc_user_class->can('username') and $bc_user->{username}) {
                ($user) = $self->bc_user_class->search( username => $bc_user->{username} );
            }
            $user = $self->bc_user_class->find_or_create({ bitcard_id => $bc_user->{id} }) unless $user;
            for my $m (qw(username email name)) {
                next unless $user->can($m);
                $user->$m($bc_user->{$m});
            }
            $user->bitcard_id($bc_user->{id});
            $user->update;
            $self->cookie($cookie_name, $user->id);
            $self->user($user);
            return $user;
        }
    }
}

sub is_logged_in {
    my $self = shift;
    my $user_info = $self->user;
    return 1 if $user_info and $user_info->{id};
    return 0;
}

sub bitcard {
  my $self = shift;
  my $site = $self->r->dir_config("site");
  my $bitcard_token = $self->config->site->{$site}->{bitcard_token};
  my $bitcard_url   = $self->config->site->{$site}->{bitcard_url};
  unless ($bitcard_token) {
    cluck "No bitcard_token configured in combust.conf for $site";
    return;
  }
  my $bc = Authen::Bitcard->new(token => $bitcard_token, @_);
  # $bc->key_cache(sub { &__bitcard_key });
  $bc->bitcard_url($bitcard_url) if $bitcard_url;

  for my $m (qw(info_required info_optional)) {
      my $bcm = "bc_$m";
      $bc->$m($self->$bcm) if $self->can($bcm);
  }
  $bc;
}

sub login_url {
    my $self = shift;
    my $bc = $self->bitcard;
    $bc->login_url( r => $self->_here_url );
}

sub account_url {
  my $self = shift;
  my $bc = $self->bitcard;
  $bc->account_url( r => $self->_here_url )
}

sub _here_url {
    my $self = shift;
    my $here = URI->new($self->config->base_url($self->site)
                      . $self->r->uri 
                      . '?' . $self->r->query_string 
                      );
    $here->as_string;
}


sub login {
    my $self = shift;
    $self->tpl_param('login_url', $self->login_url);
    return OK, $self->evaluate_template('tpl/bitcard_login.html');
}

sub show_login {
    shift->login(@_);
}

sub logout {
    my $self = shift;
    $self->cookie($cookie_name, 0);
    $self->user(undef);
    return OK, $self->onepixelgif, 'image/gif' if $self->req_param('bc-logout');
    return $self->redirect($self->bitcard->logout_url(r => $self->config->base_url($self->site) . '/'))
}

my $GIF = unpack("u", q{K1TE&.#EA`0`!`(```````````"'Y!`$`````+``````!``$```("1`$`.P``});

sub onepixelgif {
    $GIF;
}


sub user {
  my $self = shift;
  return $self->{_user} if $self->{_user};
  if (@_) { return $self->{_user} = $_[0] }
  my $uid = $self->cookie($cookie_name) or return;
  my $user = $self->bc_user_class->retrieve($uid);
  return $self->{_user} = $user if $user;
  $self->cookie($cookie_name, '0');
  return;
}




1;