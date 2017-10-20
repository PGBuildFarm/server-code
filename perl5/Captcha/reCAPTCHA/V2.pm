package Captcha::reCAPTCHA::V2;

use strict;
use warnings;

use Carp;
use HTTP::Tiny;
use JSON::PP;

# ABSTRACT: A Perl implementation of reCAPTCHA API version 2

our $VERSION = '0.3'; # VERSION


sub new {
    my $class = shift;
    my $self = bless {}, $class;

    # Initialize the user agent object
    $self->{ua} = HTTP::Tiny->new(
        agent => 'Captcha::reCAPTCHA::V2/'.
            ($Captcha::reCAPTCHA::V2::VERSION || 0) . ' (Perl)'
    );

    $self->{widget_api} = 'https://www.google.com/recaptcha/api.js?'.
                            'onload=onloadCallback&render=explicit';

    $self->{verify_api} = 'https://www.google.com/recaptcha/api/siteverify';

    return $self;
}

sub _element_id {
    my ($key) = @_;
    return 'recaptcha_' . substr($key, 0, 10);
}

=comment

sub _recaptcha_script {
    my ($self, $sitekey, $options) = @_;

    my $json_options = to_json({ sitekey => $sitekey, %$options }, $self->{json_options} || {});

    return '<script type="text/javascript">var onloadCallback = function(){grecaptcha.render(\''
        . _element_id($sitekey) . '\',' . $json_options . ');};</script>';
}

=cut

sub html {
    my ($self, $sitekey, $options) = @_;

    $options ||= {};

    if (!defined $sitekey) {
        croak 'Site key is required to use reCAPTCHA';
    }

    unless (ref $options eq "HASH") {
        croak 'Options must be a reference to hash';
    }

    my $script = $self->_recaptcha_script($sitekey, $options);

    return join(
        '',
        $script,
        '<script src="' . $self->{widget_api} . '" type="text/javascript"></script>',
        '<div id="'. _element_id($sitekey) . '"></div>',
    );
}


sub verify {
    my ($self, $secret, $response, $remoteip) = @_;

    if (!defined $secret) {
        croak 'Secret key is required to verify reCAPTCHA';
    }

    if (!defined $response) {
        croak 'Response from user is required to verify reCAPTCHA';
    }

    my $params = {
        secret    => $secret,
        response  => $response,
    };

    $params->{remoteip} = $remoteip if defined $remoteip;

    my $res = $self->{ua}->post_form(
        $self->{verify_api},
        $params
    );

    if ($res->{success}) {
        my $content = decode_json $res->{content};
        if ($content->{success}){
            return { success => 1 };
        } else {
            return { success => 0, error_codes => $content->{'error-codes'} };
        }
    }
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Captcha::reCAPTCHA::V2 - A Perl implementation of reCAPTCHA API version 2

=head1 VERSION

version 0.3

=head1 SYNOPSIS

Captcha::reCAPTCHA::V2 enables you to integrate reCAPTCHA version 2 into your
web application.

    use Captcha::reCAPTCHA::V2;

    # Create a new instance of Captcha::reCAPTCHA::V2
    my $rc = Captcha::reCAPTCHA::V2->new;

    # Get HTML code to display the reCAPTCHA
    my $rc_html = $rc->html('site key');

    # Verify user's response
    my $result = $rc->verify('secret', $response);

    if ($result->{success}){
        # Good
    } else {
        # Bad -- get first error that was returned
        $error = $result->{error_codes}->[0];
    }

=head1 METHODS

=head2 new

Creates a new instance of Captcha::reCAPTCHA::V2.

    my $rc = Captcha::reCAPTCHA::V2->new;

=head2 html

Returns the HTML code for rendering the reCAPTCHA widget.

    my $html = $rc->html('site key', { theme => 'dark' });

Parameters:

=over 4

=item * C<$sitekey>

B<(Required)> The site's public key provided by API

=item * C<$options>

A reference to a hash of options that affect the appearance and behavior of the
reCAPTCHA widget. Available options:

=over

=item * C<theme>

The color theme of the widget. Possible values are C<'dark'> and C<'light'>.

=item * C<type>

The type of the captcha to serve. Possible values are C<'audio'> and
C<'image'>.

=item * C<size>

The size of the widget. Possible values are C<'compact'> and C<'normal'>.

=back

=back

See also: L<grecaptcha.render parameters|https://developers.google.com/recaptcha/docs/display#render_param>.

=head2 verify

Verifies the user's response.

    my $result = $rc->verify('secret', $response);

    if ($result->{success}) {
        # ...
    }

Parameters:

=over 4

=item * C<$secret>

B<(Required)> The site's secret key provided by API

=item * C<$response>

B<(Required)> Response string retrieved from the submitted form field
C<g-recaptcha-response>.

=item * C<$remoteip>

IP address of the user.

=back

Returns a reference to a hash containing two fields: C<success> and C<error_codes>.

=head1 SEE ALSO

=over 4



=back

* L<Captcha::reCAPTCHA>

* L<Google reCAPTCHA API Reference|https://www.google.com/recaptcha/intro/index.html/>

=head1 ACKNOWLEDGEMENTS

Based on Andy Armstrong's a perl implementation of the reCAPTCHA API version 1
(Captcha::reCAPTCHA).

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/Sidnet/p5-Captcha-reCAPTCHA-V2/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/Sidnet/p5-Captcha-reCAPTCHA-V2>

  git clone https://github.com/Sidnet/p5-Captcha-reCAPTCHA-V2.git

=head1 AUTHOR

Pattawan Kaewduangdee <pattawan@cpan.org>

=head1 CONTRIBUTOR

=for stopwords Michal Wojciechowski

Michal Wojciechowski <odyniec@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Pattawan Kaewduangdee.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
