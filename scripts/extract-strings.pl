#!/usr/bin/perl
# Extrait les clés de traduction (format d'exécution : %@ pour un texte, %lld pour un entier).
use strict; use warnings;
binmode STDOUT, ':encoding(UTF-8)';
my (%keys, @order);
my $lit = qr/"((?:[^"\\\n]|\\.)*)"/;
my $context = qr/(?:\blocalized\(\s*|String\(localized:\s*|\b(?:Text|Button|Label|Toggle|Section|Picker|Menu|TextField|Link)\(\s*|\.(?:help|confirmationDialog)\(\s*|\b(?:text|buttonTitle|summary|actionTitle|label|title|value|help|heading|description):\s*|\?\s*(?=")|\s:\s*(?="))/;
sub is_int { my $e = shift; return $e =~ /^Int\(/ || $e =~ /(?:count|Count|done|total|succeeded|broken|dimension|statusCode)$/; }
sub to_key {
    my $s = shift; my $out = '';
    while (length $s) {
        if ($s =~ s/^\\\(//) {
            my ($depth, $expr) = (1, '');
            while (length $s) {
                my $c = substr($s, 0, 1, '');
                if ($c eq '(') { $depth++ } elsif ($c eq ')') { $depth--; last if $depth == 0 }
                $expr .= $c;
            }
            $out .= is_int($expr) ? '%lld' : '%@';
        } elsif ($s =~ s/^\\(.)//) { $out .= $1 }
        else { $out .= substr($s, 0, 1, '') }
    }
    return $out;
}
for my $file (@ARGV) {
    open my $in, '<:encoding(UTF-8)', $file or die; my $n = 0;
    while (my $line = <$in>) {
        $n++;
        next if $line =~ /^\s*\/\//;
        while ($line =~ /$context$lit/g) {
            my $raw = $1;
            next unless $raw =~ /[[:alpha:]]{2}/;                 # pas de symbole seul
            next if $raw =~ /^[a-z0-9.\-]+$/ && $raw !~ / /;      # noms d'icônes, identifiants
            next if $raw =~ m{^/|^x-apple|^https?:|\.app/|^com\.|^io\.};
            my $key = to_key($raw);
            push @order, $key unless exists $keys{$key};
            $keys{$key} //= "$file:$n";
        }
    }
}
print "$_\t$keys{$_}\n" for @order;
