#!/usr/bin/env perl

use strict;

use Crypt::OpenSSL::RSA;
use Crypt::OpenSSL::Bignum;
use JSON;
use File::Slurp;
use MIME::Base64;

my $json_file = "private_key.json";
my $json_content = read_file($json_file);
$json_content =~ tr/-/+/;
$json_content =~ tr/_/\//;

my $json = decode_json($json_content);

my $n = Crypt::OpenSSL::Bignum->new_from_bin(decode_base64($json->{n}));
my $e = Crypt::OpenSSL::Bignum->new_from_bin(decode_base64($json->{e}));
my $d = Crypt::OpenSSL::Bignum->new_from_bin(decode_base64($json->{d}));
my $p = Crypt::OpenSSL::Bignum->new_from_bin(decode_base64($json->{p}));
my $q = Crypt::OpenSSL::Bignum->new_from_bin(decode_base64($json->{q}));

my $rsa = Crypt::OpenSSL::RSA->new_key_from_parameters($n, $e, $d, $p, $q);

print($rsa->get_private_key_string());
