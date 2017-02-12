package App::RemovePdfPassword;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Perinci::Object;

our %SPEC;

$SPEC{remove_pdf_password} = {
    v => 1.1,
    summary => 'Remove password from PDF files',
    description => <<'_',

This program is a wrapper for <prog:qpdf> to remove passwords from PDF files
(in-place).

The motivation for this program is the increasing occurence of financial
institutions sending financial statements or documents in the format of
password-protected PDF file. This is annoying when we want to archive the file
or use it in an organization because we have to remember different passwords for
different financial institutions and re-enter the password everytime we want to
use the file. (The banks could've sent the PDF in a password-protected .zip, or
use PGP-encrypted email, but I digress.)

You can provide the passwords to be tried in a configuration file,
`~/remove-pdf-password.conf`, e.g.:

 passwords = pass1
 passwords = pass2
 passwords = pass3

or:

 passwords = ["pass1", "pass2", "pass3"]

_
    args => {
        files => {
            schema => ['array*', of=>'filename*', min_len=>1, uniq=>1],
            req => 1,
            pos => 0,
            greedy => 1,
            'x.completion' => [filename => {filter => sub { /\.pdf$/i }}],
        },
        passwords => {
            schema => ['array*', of=>['str*', min_len=>1], min_len=>1],
        },
        backup => {
            summary => 'Whether to backup the original file to ORIG~',
            schema => 'bool*',
            default => 1,
        },
    },
    deps => {
        prog => 'qpdf',
    },
};
sub remove_pdf_password {
    #require File::Temp;
    require IPC::System::Options;
    require Proc::ChildError;
    #require Path::Tiny;

    my %args = @_;

    my $envres = envresmulti();

  FILE:
    for my $f (@{ $args{files} }) {
        unless (-f $f) {
            $envres->add_result(404, "File not found", {item_id=>$f});
            next FILE;
        }
        # XXX test that tempfile doesn't yet exist. but actually we can't avoid
        # race condition because qpdf is another process
        my $tempf = "$f.tmp".int(rand*900_000 + 100_000);

        my $decrypted;
      PASSWORD:
        for my $p (@{ $args{passwords} }) {
            my ($stdout, $stderr);
            IPC::System::Options::system(
                {log => 1, capture_stdout => \$stdout, capture_stderr => \$stderr},
                "qpdf", "--password=$p", "--decrypt", $f, $tempf);
            my $err = $? ? Proc::ChildError::explain_child_error() : '';
            if ($err && $err =~ /: invalid password$/) {
                next PASSWORD;
            } elsif ($err) {
                $envres->add_result(500, $err, {item_id=>$f});
                next FILE;
            }
        }

      BACKUP:
        {
            last unless $args{backup};
            unless (rename $f, "$f~") {
                warn "Can't backup original '$f' to '$f~': $!, skipped backup\n";
                last;
            };
        }
        unless (rename $tempf, $f) {
            $env->add_result(500, "Can't rename $tempf to $f: $!", {item_id=>$f});
            next FILE;
        }
        $env->add_result(200, "OK", {item_id=>$f});
    }

    $envres->as_struct;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<remove-pdf-password>.

=cut
