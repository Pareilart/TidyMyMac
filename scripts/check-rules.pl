#!/usr/bin/perl
# Vérifie les règles de nettoyage intégrées et les profils (Resources/Rules/*.json) :
# champs obligatoires, niveau de risque, identifiants uniques et traduction dans chaque langue de l'app.
use strict;
use warnings;
use JSON::PP;

my @languages = map { m{/(\w+)\.lproj$} ? $1 : () } glob('Resources/Localization/*.lproj');
my %risks = map { $_ => 1 } qw(safe review irreversible);
my %targets = map { $_ => 1 } qw(contents location search);
my %tints = map { $_ => 1 } qw(mint aqua sky lavender rose lime peach amber coral);
my (%seen, %profiles, @problems);
my ($count, $profileCount) = (0, 0);

sub translated {
    my ($where, $object, @fields) = @_;
    for my $field (@fields) {
        my $text = $object->{$field};
        if (ref $text ne 'HASH') { push @problems, "$where : $field doit être traduit dans chaque langue"; next; }
        push @problems, "$where : $field sans traduction « $_ »" for grep { !length($text->{$_} // '') } @languages;
    }
}

sub paths {
    my ($where, $field, $paths) = @_;
    if (ref $paths ne 'ARRAY' || !@$paths) { push @problems, "$where : $field manquant"; return; }
    push @problems, "$where : « $_ » doit commencer par / ou ~" for grep { !m{^(/|~$|~/)} } @$paths;
}

for my $file (sort glob('Resources/Rules/*.json')) {
    open my $fh, '<:raw', $file or die "$file : $!\n";
    my $json = eval { JSON::PP->new->decode(do { local $/; <$fh> }) };
    if (!$json) { push @problems, "$file : JSON invalide ($@)"; next; }
    if (my $profile = $json->{profile}) {
        my $where = "$file, profil " . ($profile->{id} // '?');
        $profileCount++;
        push @problems, "$where : id manquant" unless $profile->{id};
        push @problems, "$where : id de profil déjà utilisé" if $profile->{id} && $profiles{ $profile->{id} }++;
        push @problems, "$where : icon manquant" unless $profile->{icon};
        push @problems, "$where : tint inconnu" unless $tints{ $profile->{tint} // '' };
        paths($where, 'detect', $profile->{detect});
        translated($where, $profile, qw(title detail));
    }
    my $index = 0;
    for my $rule (@{ $json->{rules} || [] }) {
        my $where = "$file, " . ($rule->{id} // "règle $index");
        $index++;
        $count++;
        push @problems, "$where : id manquant" unless $rule->{id};
        push @problems, "$where : id déjà utilisé" if $rule->{id} && $seen{ $rule->{id} }++;
        push @problems, "$where : icon manquant" unless $rule->{icon};
        push @problems, "$where : risk doit valoir safe, review ou irreversible" unless $risks{ $rule->{risk} // '' };
        my $target = $rule->{target} // 'contents';
        push @problems, "$where : target doit valoir contents, location ou search" unless $targets{$target};
        push @problems, "$where : search demande des noms (names)"
            if $target eq 'search' && (ref $rule->{names} ne 'ARRAY' || !@{ $rule->{names} });
        paths($where, 'locations', $rule->{locations});
        translated($where, $rule, qw(title detail afterRemoval));
    }
}

if (@problems) {
    print "règles : problèmes\n";
    print "  $_\n" for @problems;
    exit 1;
}
print "règles : $count règles et $profileCount profils valides, traduits en " . join(', ', @languages) . "\n";
