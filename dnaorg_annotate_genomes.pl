#!/usr/bin/env perl
# EPN, Mon Aug 10 10:39:33 2015
#
use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw(gettimeofday);
use Bio::Easel::MSA;
use Bio::Easel::SqFile;

# hard-coded-paths:
my $idfetch       = "/netopt/ncbi_tools64/bin/idfetch";
my $esl_fetch_cds = "/panfs/pan1/dnaorg/programs/esl-fetch-cds.pl";

# The definition of $usage explains the script and usage:
my $usage = "\ndnaorg_annotate_genomes.pl\n";
$usage .= "\t<directory created by dnaorg_fetch_dna_wrapper>\n";
$usage .= "\t<list file with all accessions>\n";
$usage .= "\n"; 
$usage .= " This script annotates genomes from the same species based\n";
$usage .= " on reference annotation.\n";
$usage .= "\n";
$usage .= " BASIC OPTIONS:\n";
$usage .= "  -oseq <s>  : identify origin sequence <s> in genomes, put | at site of origin, e.g. TAATATT|AC\n";
$usage .= "  -strict    : require matching annotations to match CDS/exon index\n";
$usage .= "  -nodup     : do not duplicate each genome to allow identification of features that span stop..start\n";
$usage .= "  -notexon   : do not use exon-specific models\n";
$usage .= "  -onlybuild : exit after building reference models\n";
$usage .= "  -model <s> : use model file <s>, instead of building one\n";
$usage .= "\n OPTIONS CONTROLLING OUTPUT TABLE:\n";
$usage .= "  -c         : concise output mode (enables -nomdlb -noexist -nobrack and -nostop)\n";
$usage .= "  -nomdlb    : do not add model boundary annotation to output\n";
$usage .= "  -noexist   : do not include information on existing annotation\n";
$usage .= "  -nobrack   : do not include brackets around predicted annotations that do not match existing\n";
$usage .= "  -nostop    : do not output stop codon for each predicted CDS\n";
$usage .= "  -nofid     : do not output fractional identity relative to reference for each CDS/exon\n";
$usage .= "  -noss3     : do not output results of start codon, stop codon and multiple of 3 tests\n";
$usage .= "  -noolap    : do not output overlap information\n";
$usage .= "  -noexp     : do not output explanation of column headings\n";
$usage .= "\n OPTIONS FOR SELECTING HOMOLOGY SEARCH ALGORITHM:\n";
$usage .= "  -inf     : use Infernal 1.1 for predicting annotations, default: use HMMER3's nhmmscan\n";
$usage .= "\n OPTIONS SPECIFIC TO HMMER3:\n";
$usage .= "  -hmmenv  : use HMM envelope boundaries for predicted annotations, default: use window boundaries\n";
$usage .= "\n OPTIONS SPECIFIC TO INFERNAL:\n";
$usage .= "  -iglocal  : use the -g option with cmsearch for glocal searches\n";
$usage .= "  -cslow    : use default cmcalibrate parameters, not parameters optimized for speed (requires --inf1p1)\n";
$usage .= "  -ccluster : submit calibration to cluster and exit (requires --onlybuild and --inf1p1)\n";

$usage .= "\n";

my ($seconds, $microseconds) = gettimeofday();
my $start_secs      = ($seconds + ($microseconds / 1000000.));
my $executable      = $0;
my $hmmer_exec_dir  = "/home/nawrocke/bin/";
my $inf_exec_dir    = "/usr/local/infernal/1.1.1/bin/";
my $hmmbuild        = $hmmer_exec_dir  . "hmmbuild";
my $hmmpress        = $hmmer_exec_dir  . "hmmpress";
my $hmmalign        = $hmmer_exec_dir  . "hmmalign";
my $hmmfetch        = $hmmer_exec_dir  . "hmmfetch";
my $nhmmscan        = $hmmer_exec_dir  . "nhmmscan";
my $cmbuild         = $inf_exec_dir . "cmbuild";
my $cmcalibrate     = $inf_exec_dir . "cmcalibrate";
my $cmpress         = $inf_exec_dir . "cmpress";
my $cmscan          = $inf_exec_dir . "cmscan";
my $cmalign         = $inf_exec_dir . "cmalign";
my $cmfetch         = $inf_exec_dir . "cmfetch";

foreach my $x ($hmmbuild, $hmmpress, $nhmmscan, $cmbuild, $cmcalibrate, $cmpress, $cmscan) { 
  if(! -x $x) { die "ERROR executable file $x does not exist (or is not executable)"; }
}

my $origin_seq   = undef; # defined if -oseq      enabled
my $do_strict    = 0; # set to '1' if -strict     enabled, matching annotations must be same index CDS+exon, else any will do
my $do_nodup     = 0; # set to '1' if -nodup      enabled, do not duplicate each genome, else do 
my $do_notexon   = 0; # set to '1' if -noexon     enabled, do not use exon-specific models, else do
my $do_onlybuild = 0; # set to '1' if -onlybuild  enabled, exit after building the model
my $in_model_db  = undef; # defined if -model <s> enabled, use <s> as the model file instead of building one
# options for controlling output table
my $do_concise   = 0; # set to '1' if -c       enabled, invoke concise output mode, set's all $do_no* variables below to '1'
my $do_nomdlb    = 0; # set to '1' if -nomdlb  or -c enabled, do not print HMM boundary info for annotations, else do
my $do_noexist   = 0; # set to '1' if -noexist or -c enabled, do not output information on existing annotations
my $do_nobrack   = 0; # set to '1' if -nobrack or -c enabled, do not output brackets around predicted annotations that do not match any existing annotation
my $do_nostop    = 0; # set to '1' if -nostop  or -c enabled, do not output stop codon for predicted annotations
my $do_nofid     = 0; # set to '1' if -nofid   or -c enabled, do not output fractional identities relative to the reference
my $do_noss3     = 0; # set to '1' if -noss3   or -c enabled, do not output SS3 columns: 'S'tart codon check, 'S'top codon check and multiple of '3' check
my $do_noolap    = 0; # set to '1' if -noolap  or -c enabled, do not output information on overlapping CDS/exons
my $do_noexp     = 0; # set to '1' if -noexp   or -c enabled, do not output explanatory information about column headings
# options for controlling homology search method
my $do_inf       = 0; # set to '1' if -inf1p1     enabled, use Infernal 1.1, not HMMER3's nhmmscan
# options specific to HMMER3
my $do_hmmenv    = 0; # set to '1' if -hmmenv     enabled, use HMM envelope boundaries as predicted annotations, else use window boundaries
# options specific to Infernal
my $do_iglocal   = 0; # set to '1' if -iglocal    enabled, use -g with cmsearch
my $do_cslow     = 0; # set to '1' if -cslow      enabled, use default, slow, cmcalibrate parameters instead of speed optimized ones
my $do_ccluster  = 0; # set to '1' if -ccluster   enabled, submit calibration to cmcalibrate

&GetOptions("oseq=s"    => \$origin_seq,
            "strict"    => \$do_strict,
            "nodup"     => \$do_nodup,
            "notexon"   => \$do_notexon,
            "onlybuild" => \$do_onlybuild,
            "model=s"   => \$in_model_db,
            "c"         => \$do_concise,
            "nomdlb"    => \$do_nomdlb,
            "noexist"   => \$do_noexist,
            "nobrack"   => \$do_nobrack,
            "nostop"    => \$do_nostop,
            "nofid"     => \$do_nofid,
            "noss3"     => \$do_noss3,
            "noolap"    => \$do_noolap,
            "noexp"     => \$do_noexp,
            "inf"       => \$do_inf,
            "hmmenv"    => \$do_hmmenv,
            "iglocal"   => \$do_iglocal,
            "cslow"     => \$do_cslow, 
            "ccluster"  => \$do_ccluster) ||
    die "Unknown option";

if(scalar(@ARGV) != 2) { die $usage; }
my ($dir, $listfile) = (@ARGV);

#$dir =~ s/\/*$//; # remove trailing '/' if there is one
#my $outdir     = $dir;
#my $outdirroot = $outdir;
#$outdirroot =~ s/^.+\///;

# store options used, so we can output them 
my $opts_used_short = "";
my $opts_used_long  = "";
if(defined $origin_seq) { 
  $opts_used_short .= "-oseq ";
  $opts_used_long  .= "# option:  searching for origin sequence of $origin_seq [-oseq]\n";
}
if($do_strict) { 
  $opts_used_short .= "-strict ";
  $opts_used_long  .= "# option:  demand matching annotations are same indexed CDS/exon [-strict]\n";
}
if($do_nodup) { 
  $opts_used_short .= "-nodup ";
  $opts_used_long  .= "# option:  not duplicating genomes, features that span the end..start will be undetectable [-nodup]\n";
}
if($do_notexon) { 
  $opts_used_short .= "-notexon ";
  $opts_used_long  .= "# option:  using full CDS, and not exon-specific models, for CDS with multiple exons [-noexon]\n";
}
if($do_onlybuild) { 
  $opts_used_short .= "-onlybuild ";
  $opts_used_long  .= "# option:  exit after model construction step [-onlybuild]\n";
}
if(defined $in_model_db) { 
  $opts_used_short .= "-model $in_model_db ";
  $opts_used_long  .= "# option:  use model in $in_model_db instead of building one here [-model]\n";
}
if($do_concise) { 
  $opts_used_short .= "-c ";
  $opts_used_long  .= "# option:  concise output mode [-c]\n";
}
if($do_nomdlb) { 
  $opts_used_short .= "-nomdlb ";
  $opts_used_long  .= "# option:  do not output HMM boundaries of predicted annotations [-nomdlb]\n";
}
if($do_noexist) { 
  $opts_used_short .= "-noexist";
  $opts_used_long  .= "# option:  not outputting info on existing annotations [-noexist]\n";
}
if($do_nobrack) { 
  $opts_used_short .= "-nobrack";
  $opts_used_long  .= "# option:  not putting brackets around predicted start/stop positions [-nobrack]\n";
}
if($do_nostop) { 
  $opts_used_short .= "-nostop";
  $opts_used_long  .= "# option:  do not output stop codons [-nostop]\n";
}
if($do_nofid) { 
  $opts_used_short .= "-nofid";
  $opts_used_long  .= "# option:  do not output fractional identities [-nofid]\n";
}
if($do_noss3) { 
  $opts_used_short .= "-noss3";
  $opts_used_long  .= "# option:  do not output start codon, stop codon or multiple of 3 test results [-noss3]\n";
}
if($do_noolap) { 
  $opts_used_short .= "-noolap";
  $opts_used_long  .= "# option:  do not output information on overlaps [-noolap]\n";
}
if($do_noexp) { 
  $opts_used_short .= "-noexp";
  $opts_used_long  .= "# option:  do not output information on column headings [-noexp]\n";
}
if($do_inf) { 
  $opts_used_short .= "-inf";
  $opts_used_long  .= "# option:  using Infernal 1.1 for predicting annotation [-inf]\n";
}
if($do_hmmenv) { 
  $opts_used_short .= "-hmmenv ";
  $opts_used_long  .= "# option:  use HMM envelope boundaries as predicted annotations, not window boundaries [-hmmenv]\n";
}
if($do_iglocal) { 
  $opts_used_short .= "-iglocal ";
  $opts_used_long  .= "# option:  use glocal search option with Infernal [-iglocal]\n";
}
if($do_cslow) { 
  $opts_used_short .= "-cslow ";
  $opts_used_long  .= "# option:  run cmcalibrate in default (slow) mode [-cslow]\n";
}
if($do_ccluster) { 
  $opts_used_short .= "-ccluster ";
  $opts_used_long  .= "# option:  submit calibration job to cluster [-ccluster]\n";
}
# 
# check for incompatible option values/combinations:
if($do_inf && $do_hmmenv) { 
  die "ERROR -hmmenv is incompatible with --inf"; 
}

# check that options that must occur in combination, do
if($do_ccluster && (! $do_onlybuild)) { 
  die "ERROR -ccluster must be used in combination with -onlybuild"; 
}
if($do_ccluster && (! $do_inf)) { 
  die "ERROR -ccluster must be used in combination with -inf"; 
}
if($do_cslow && (! $do_inf)) { 
  die "ERROR -cslow must be used in combination with -inf"; 
}

# check that input files related to options actually exist
if(defined $in_model_db) { 
  if(! -s $in_model_db) { die "ERROR: $in_model_db file does not exist"; }
}
# verify origin sequence if necessary
my $origin_offset = undef;
if(defined $origin_seq) { 
  $origin_offset = validateOriginSeq($origin_seq);
  $origin_seq =~ s/\|//;
}

# if in $concise output mode, turn on other affected options:
if($do_concise) { 
  $do_nomdlb =  1;
  $do_noexist = 1;
  $do_nobrack = 1;
  $do_nostop  = 1;
  $do_nofid   = 1;
  $do_noss3   = 1;
  $do_noolap  = 1;
}

###############
# Preliminaries
###############
# check if the $dir exists, and that it contains a .gene.tbl file, and a .length file
if(! -d $dir)      { die "ERROR directory $dir does not exist"; }
if(! -s $listfile) { die "ERROR list file $listfile does not exist, or is empty"; }
my $dir_tail = $dir;
$dir_tail =~ s/^.+\///; # remove all but last dir
my $gene_tbl_file  = $dir . "/" . $dir_tail . ".gene.tbl";
my $cds_tbl_file   = $dir . "/" . $dir_tail . ".CDS.tbl";
my $length_file    = $dir . "/" . $dir_tail . ".length";
my $out_root = $dir . "/" . $dir_tail;
#if(! -s $gene_tbl_file) { die "ERROR $gene_tbl_file does not exist."; }
if(! -s $cds_tbl_file)  { die "ERROR $cds_tbl_file does not exist."; }
if(! -s $length_file)   { die "ERROR $length_file does not exist."; }

# output banner
my $script_name = "dnaorg_annotate_genomes.pl";
my $script_desc = "Annotate genomes based on a reference and homology search";
print ("# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n");
print ("# $script_name: $script_desc\n");
print ("# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n");
print ("# command: $executable $opts_used_short $dir $listfile\n");
printf("# date:    %s\n", scalar localtime());
if($opts_used_long ne "") { 
  print $opts_used_long;
}
printf("#\n");

#####################
# parse the list file
#####################
my @accn_A = (); # array of accessions
open(IN, $listfile) || die "ERROR unable to open $listfile for reading"; 
my $waccn = 0; # max length of all accessions
while(my $accn = <IN>) { 
  if($accn =~ m/\w/) { 
    chomp $accn;
    stripVersion(\$accn); # remove version
    push(@accn_A, $accn);
    if(length($accn) > $waccn) { $waccn = length($accn); }
  }
}
close(IN); 

my $head_accn = $accn_A[0];

##################################
# parse the table and length files
##################################
my %gene_tbl_HHA = ();  # Data from .gene.tbl file
                        # 1D: key: accession
                        # 2D: key: column name in gene ftable file
                        # 3D: per-row values for each column
my %cds_tbl_HHA = ();   # Data from .cds.tbl file
                        # hash of hashes of arrays, 
                        # 1D: key: accession
                        # 2D: key: column name in gene ftable file
                        # 3D: per-row values for each column
my %totlen_H = (); # key: accession, value length read from length file

parseLength($length_file, \%totlen_H);

parseTable($gene_tbl_file, \%gene_tbl_HHA);
parseTable($cds_tbl_file, \%cds_tbl_HHA);

#######################
# variable declarations
#######################
my $strand_str;              # +/- string for all CDS for an accession: e.g. '+-+': 1st and 3rd CDS are + strand, 2nd is -

# reference information on reference accession, first accession read in ntlist file
my $ref_accn          = undef; # changed to <s> with -ref <s>
my $ref_label_str     = undef; # label string for reference accn
my $ref_ncds          = 0;     # number of CDS in reference
my $ref_strand_str    = "";    # strand string for reference 
my @ref_cds_len_A     = ();    # [0..$i..$ref_ncds-1]: length of each reference CDS
#my @ref_cds_len_tol_A = ();   # [0..$i..$ref_ncds-1]: length tolerance, any gene that is within this fraction of the lenght of the ref gene is a match
my @ref_cds_coords_A  = ();    # [0..$i..$ref_ncds-1]: CDS coords for reference
my @ref_cds_product_A = ();    # CDS:product qualifier data for reference 

my $ncds = 0;              # number of CDS
my $npos = 0;              # number of CDS on positive strand
my $nneg = 0;              # number of CDS on negative strand
my $nunc = 0;              # number of CDS on uncertain strand
my $nbth = 0;              # number of CDS on both strands
my @cds_len_A = ();        # [0..$i..$ncds-1] length of CDS $i
my @cds_coords_A = ();     # [0..$i..$ncds-1] coords of CDS $i
my @cds_product_A = ();    # [0..$i..$ncds-1] CDS:product annotation for CDS $i
my @cds_protid_A = ();     # will remain empty unless $do_protid is 1 (-protid enabled at cmdline)
my @cds_codonstart_A = (); # will remain empty unless $do_codonstart is 1 (-codonstart enabled at cmdline)
#my $do_desc = ($do_product || $do_protid || $do_codonstart) ? 1 : 0; # '1' to create a description to add to defline of fetched sequences, '0' not to

#####################################################
# Fetch all genome sequences, including the reference
#####################################################
my $naccn = scalar(@accn_A);
my $gnm_fetch_file = $out_root . ".fg.idfetch.in";
my $gnm_fasta_file = $out_root . ".fg.fa";
my @seq_accn_A = (); # [0..$naccn-1] name of genome fasta sequence for each accn
my $seq_accn;     # temp fasta sequence name
my $fetch_string = undef;
my $ref_seq_accn; # name of fasta sequence for reference
open(OUT, ">" . $gnm_fetch_file) || die "ERROR unable to open $gnm_fetch_file";
for(my $a = 0; $a < $naccn; $a++) { 
#  print OUT $accn_A[$a] . "\n";
  my $accn = $accn_A[$a];
  if(! exists $totlen_H{$accn}) { die "ERROR no total length read for accession $accn"; } 
  if($do_nodup) { 
    $fetch_string = $accn . ":1.." . $totlen_H{$accn} . "\n";
    print OUT $accn . ":" . "genome" . "\t" . $fetch_string;
    $seq_accn = $accn . ":genome:" . $accn . ":1:" . $totlen_H{$accn} . ":+:";
  }
  else { 
    $fetch_string = "join(" . $accn . ":1.." . $totlen_H{$accn} . "," . $accn . ":1.." . $totlen_H{$accn} . ")\n";
    print OUT $accn . ":" . "genome-duplicated" . "\t" . $fetch_string;
    $seq_accn = $accn . ":genome-duplicated:" . $accn . ":1:" . $totlen_H{$accn} . ":+:" . $accn . ":1:" . $totlen_H{$accn} . ":+:";
  }
  push(@seq_accn_A, $seq_accn);
  if($a == 0) { $ref_seq_accn = $seq_accn; }
}
close(OUT);

# remove the file we're about to create ($gnm_fasta_file), and any .ssi index that may exist with it
if(-e $gnm_fasta_file)          { unlink $gnm_fasta_file; }
if(-e $gnm_fasta_file . ".ssi") { unlink $gnm_fasta_file . ".ssi"; }

printf("%-50s ... ", sprintf("# Fetching $naccn full%s genome sequences", $do_nodup ? "" : " (duplicated)"));
# my $cmd = "$idfetch -t 5 -c 1 -G $gnm_fetch_file > $gnm_fasta_file";
my $cmd = "perl $esl_fetch_cds -nocodon $gnm_fetch_file > $gnm_fasta_file";
my $secs_elapsed = runCommand($cmd, 0);
printf("done. [%.1f seconds]\n", $secs_elapsed);

# and open the sequence file using BioEasel
my $sqfile = Bio::Easel::SqFile->new({ fileLocation => $gnm_fasta_file });

##################################################
# If we're looking for an origin sequence, do that
##################################################
my %origin_coords_HA = ();
if(defined $origin_seq) {
  findSeqInFile($sqfile, $origin_seq, $do_nodup, \%origin_coords_HA);
}

########################################################
# Gather information and sequence data on the reference.
# Use each reference CDS and reference CDS exon as a 
# homology search model against all the genomes.
#######################################################
$ref_accn = $accn_A[0];
if(! exists ($cds_tbl_HHA{$ref_accn})) { die "ERROR no CDS information stored for reference accession"; }
(undef, undef, undef, undef, undef, $ref_strand_str) = getStrandStats(\%cds_tbl_HHA, $ref_accn);
getLengthStatsAndCoordStrings(\%cds_tbl_HHA, $ref_accn, \@ref_cds_len_A, \@ref_cds_coords_A);
getQualifierValues(\%cds_tbl_HHA, $ref_accn, "product", \@ref_cds_product_A);
$ref_ncds = scalar(@ref_cds_len_A);

my $all_stk_file = $out_root . ".ref.all.stk";

($seconds, $microseconds) = gettimeofday();
my $start_time = ($seconds + ($microseconds / 1000000.));
printf("%-50s ... ", "# Fetching reference CDS sequences");
my $cur_out_root;
my $cur_name_root;
my $fetch_input;
my $fetch_output;
my $nhmm = 0;               # number of HMMs (and alignments used to build those HMMs)
my @hmm2cds_map_A = ();     # [0..h..$nhmm-1]: $i: HMM ($h+1) maps to reference cds ($i+1)
my @hmm2exon_map_A = ();    # [0..h..$nhmm-1]: $e: HMM ($h+1) maps to exon ($e+1) of reference cds $hmm2cds_map_A[$h]+1
my @hmm_is_first_A = ();    # [0..h..$nhmm-1]: '1' if HMM ($h+1) is the first one for cds $hmm2cds_map_A[$h], else 0
my @hmm_is_final_A = ();    # [0..h..$nhmm-1]: '1' if HMM ($h+1) is the final one for cds $hmm2cds_map_A[$h], else 0
my @model_A = ();           # [0..$nhmm-1]: array of model HMM names, also name of stockholm alignments used to build those HMMs
my @cds_out_short_A   = (); # [0..$ref_ncds-1]: array of abbreviated model CDS names to print
my @cds_out_product_A = (); # [0..$ref_ncds-1]: array of 'CDS:product' qualifier (protein names)
my %mdllen_H          = (); # key: model name from @model_A, value is model length
my @ref_nexons_A      = ();
my $ref_tot_nexons    = 0;

# for each reference CDS, fetch each exon (or the full CDS if -notexon enabled)
for(my $i = 0; $i < $ref_ncds; $i++) { 
  # printf("REF CDS $i $ref_cds_product_A[$i]\n");
  
  # determine start and stop positions of all exons
  my @starts_A = ();
  my @stops_A  = ();
  my $nexons   = 0;
  startStopsFromCoords($ref_cds_coords_A[$i], \@starts_A, \@stops_A, \$nexons);
  push(@ref_nexons_A, $nexons);
  $ref_tot_nexons += $nexons;

  # if we're on the negative strand, reverse the arrays, they'll be in the incorrect order
  my $strand = substr($ref_strand_str, $i, 1);
  if($strand eq "-") { 
    @starts_A = reverse @starts_A;
    @stops_A  = reverse @stops_A;
  }

  # are we going to fetch multiple exons?
  my $cur_multi_exon = ($nexons == 1 || $do_notexon) ? 0 : 1;
  my $act_nexons = $nexons;
  if(! $cur_multi_exon) { $nexons = 1; }

  # for each exon, note that if $do_notexon is true, $nexons was redefined as 1 above
  for(my $e = 0; $e < $nexons; $e++) { 
    if($cur_multi_exon) { 
      $cur_out_root  = $out_root . ".ref.cds." . ($i+1) . ".exon." . ($e+1);
      $cur_name_root = $dir_tail . ".ref.cds." . ($i+1) . ".exon." . ($e+1);
    }
    else { 
      $cur_out_root  = $out_root . ".ref.cds." . ($i+1);
      $cur_name_root = $dir_tail . ".ref.cds." . ($i+1);
    }
    
    # determine start and stop of the region we are going to fetch
    my $start = ($cur_multi_exon) ? $starts_A[$e] : $starts_A[0];
    my $stop  = ($cur_multi_exon) ? $stops_A[$e]  : $stops_A[$nexons-1]; 
    if($strand eq "-") { # swap start and stop
      my $tmp = $start;
      $start = $stop;
      $stop  = $tmp;
    }
    my @fetch_AA = ();
    push(@fetch_AA, [$cur_name_root, $start, $stop, $ref_seq_accn]);
    
    # fetch the sequence
    my $cur_fafile = $cur_out_root . ".fa";
    $sqfile->fetch_subseqs(\@fetch_AA, undef, $cur_fafile);
    
    # reformat to stockholm
    my $cur_stkfile = $cur_out_root . ".stk";
    my $cmd = "esl-reformat --informat afa stockholm $cur_fafile > $cur_stkfile";
    runCommand($cmd, 0);
    
    # annotate the stockholm file with a blank SS and with a name
    my $do_blank_ss = ($do_inf); # add a blank SS_cons line if we're using Infernal
    my $cur_named_stkfile = $cur_out_root . ".named.stk";
    my $mdllen = annotateStockholmAlignment($cur_name_root, $do_blank_ss, $cur_stkfile, $cur_named_stkfile);

    # store information on this model's name for output purposes
    if($e == ($nexons-1)) { 
      my $short = sprintf("CDS #%d", ($i+1));
      if($act_nexons > 1) { $short .= " [$act_nexons exons; $strand]"; }
      else                { $short .= " [single exon; $strand]"; }
      push(@cds_out_short_A,   $short);
      push(@cds_out_product_A, $ref_cds_product_A[$i]);
    }
    push(@model_A, $cur_name_root);
    $mdllen_H{$cur_name_root} = $mdllen;

    # now append the named alignment to the growing stockholm alignment database $all-stk_file
    $cmd = "cat $cur_named_stkfile";
    if($nhmm == 0) { $cmd .= " >  $all_stk_file"; }
    else           { $cmd .= " >> $all_stk_file"; }
    runCommand($cmd, 0);
    push(@hmm2cds_map_A,  $i);
    push(@hmm2exon_map_A, $e);
    push(@hmm_is_first_A, ($e == 0)           ? 1 : 0);
    push(@hmm_is_final_A, ($e == ($nexons-1)) ? 1 : 0);
    $nhmm++;
  }
}
($seconds, $microseconds) = gettimeofday();
my $stop_time = ($seconds + ($microseconds / 1000000.));
printf("done. [%.1f seconds]\n", ($stop_time - $start_time));

# homology search section
my $model_db; # model database file, either HMMs or CMs

# first, create the model database, unless it was passed in:
if(defined $in_model_db) { 
  $model_db = $in_model_db;
}
else { 
  if($do_inf) { 
    createCmDb($cmbuild, $cmcalibrate, $cmpress, $do_cslow, $do_ccluster, $all_stk_file, $out_root . ".ref");
    if($do_onlybuild) { 
      printf("#\n# Model construction %s. Exiting.\n", ($do_ccluster) ? "job submitted." : "complete");
      exit 0;
    }
    $model_db = $out_root . ".ref.cm";
  }
  else { # use HMMER3's nhmmscan
    createHmmDb($hmmbuild, $hmmpress, $all_stk_file, $out_root . ".ref");
    if($do_onlybuild) { 
      printf("#\n# Model construction complete. Exiting.\n");
      exit 0;
    }
    $model_db = $out_root . ".ref.hmm";
  }
}
  
# now we know we have a model database, perform the search and parse the results
# output files from homology searches
my $tblout = $out_root . ".tblout"; # tabular output file, created by either nhmmscan or cmsearch
my $stdout = $out_root . ".stdout"; # standard output file from either nhmmscan or cmsearch

# 2D hashes for storing the search results
# For all of these: 1D key: model name, 2D key: sequence name,
# and the value is for the top-scoring hit only
my %p_start_HH    = (); # start positions of hits
my %p_stop_HH     = (); # stop positions of hits
my %p_strand_HH   = (); # strands of hits
my %p_score_HH    = (); # bit score of hits 
my %p_hangover_HH = (); # "<a>:<b>" where <a> is number of 5' model positions not in the alignment
                        # and <b> is number of 3' model positions not in the alignment
my %p_fid2ref_HH  = (); # fractional identity to reference 

if($do_inf) { 
  runCmscan($cmscan, $do_iglocal, $model_db, $gnm_fasta_file, $tblout, $stdout);
  parseCmscanTblout($tblout, \%totlen_H, \%mdllen_H, \%p_start_HH, \%p_stop_HH, \%p_strand_HH, \%p_score_HH, \%p_hangover_HH);
  alignHits($cmalign, $cmfetch, $model_db, $sqfile, \@model_A, \@seq_accn_A, \%totlen_H, \%p_start_HH, \%p_stop_HH, \%p_strand_HH, \%p_fid2ref_HH, $out_root);
}
else { 
  runNhmmscan($nhmmscan, $model_db, $gnm_fasta_file, $tblout, $stdout);
  parseNhmmscanTblout($tblout, $do_hmmenv, \%totlen_H, \%p_start_HH, \%p_stop_HH, \%p_strand_HH, \%p_score_HH, \%p_hangover_HH);
  alignHits($hmmalign, $hmmfetch, $model_db, $sqfile, \@model_A, \@seq_accn_A, \%totlen_H, \%p_start_HH, \%p_stop_HH, \%p_strand_HH, \%p_fid2ref_HH, $out_root);
}

printf("#\n");
printf("#\n");


#######################################################################
# Pass through all accessions, and output predicted annotation for each
#######################################################################
my $width;  # width of a field
my $pad;    # string of all spaces used for pretty formatting
my @ref_ol_AA = (); # 2D array that describes the overlaps in the reference, $ref_ol_AA[$i][$j] is '1' if the exons modeled by model $i and $j overlap
my $width_result = 5 + $ref_tot_nexons + 2;

for(my $a = 0; $a < $naccn; $a++) { 
  my $accn = $accn_A[$a];
  my $seq_accn = $seq_accn_A[$a];
  # sanity checks
  if(! exists $totlen_H{$accn}) { die "ERROR accession $accn does not exist in the length file $length_file"; }
  
  ###########################################################
  # Create the column headers if this is the first accession.
  if($a == 0) { 
    # line 1 of column headers
    printf("%-20s  %6s", "#", "");
    if(defined $origin_seq) { 
      printf("  %22s", "");
    }
    # for each CDS, output the topmost column header
    $width = 0;
    for(my $h = 0; $h < $nhmm; $h++) { 
      $width += 18;
      my $cds_i = $hmm2cds_map_A[$h];
      if(! $do_nofid)  { $width += 6; }
      if(! $do_nomdlb) { $width += 4; }
      if($hmm_is_final_A[$h]) { 
        $width += 7;
        if(! $do_noss3)  { $width += 4; }
        if(! $do_nostop) { $width += 4; }
        printf("    %*s", $width, $cds_out_short_A[$cds_i] . monocharacterString(($width-length($cds_out_short_A[$cds_i]))/2, " "));
        $width = 0;
      }
    }
    printf("  %6s", "");
    printf("  %5s", "");
    if(! $do_noexist) { 
      printf("    %19s", "");
    }
    printf("  %*s", $width_result, "");
    printf("\n");
    
    # line 2 of column headers
    printf("%-20s  %6s", "#", "");
    if(defined $origin_seq) { 
      printf("  %22s", "   origin sequence");
    }
    # for each CDS, output the second column header
    $width = 0;
    for(my $h = 0; $h < $nhmm; $h++) { 
      $pad = "";
      $width += 18;
      my $cds_i = $hmm2cds_map_A[$h];
      if(! $do_nofid)  { $width += 6; }
      if(! $do_nomdlb) { $width += 4; }
      if($hmm_is_final_A[$h]) { 
        $width += 7;
        if(! $do_noss3)  { $width += 4; }
        if(! $do_nostop) { $width += 4; }
        printf("    %*s", $width, substr($cds_out_product_A[$cds_i], 0, $width) . monocharacterString(($width-length($cds_out_product_A[$cds_i]))/2, " "));
        $width = 0;
      }
      else { 
        $width += 2;
      }
    }
    printf("  %6s", "");
    printf("  %5s", "");
    if(! $do_noexist) { 
      printf(" %19s", "existing annotation");
    }
    printf("  %*s", $width_result, "");
    printf("\n");
    
    # line 3 of column headers 
    printf("%-20s  %6s", "#", "");
    if(defined $origin_seq) { 
      printf("  %22s", "----------------------");
    }
    $width = 0;
    for(my $h = 0; $h < $nhmm; $h++) { 
      $width += 18;
      if(! $do_nofid)  { $width += 6; }
      if(! $do_nomdlb) { $width += 4; }
      if($hmm_is_final_A[$h]) { 
        $width += 9;
        if(! $do_noss3)  { $width += 4; }
        if(! $do_nostop) { $width += 4; }
        printf("  %s", monocharacterString($width, "-"));
        $width = 0;
      }
      else { 
        $width += 1;
      }
    }
#    printf("  %6s  %-*s", "", $width_result, "");
    printf("  %6s", "");
    printf("  %5s", "");
    if(! $do_noexist) { 
      printf("  %19s", "-------------------");
    }
    printf("  %-*s", $width_result, "");
    printf("\n");
    
    # line 4 of column headers
    printf("%-20s  %6s", "# accession", "totlen");
    if(defined $origin_seq) {
      printf(" %2s %5s %5s %5s %2s", " #", "start", "stop", "offst", "PF");
    }
    for(my $h = 0; $h < $nhmm; $h++) { 
      printf("  %8s %8s", 
             sprintf("%s%s", "start", $hmm2exon_map_A[$h]+1), 
             sprintf("%s%s", "stop",  $hmm2exon_map_A[$h]+1));
      if(! $do_nofid) { 
        printf(" %5s", sprintf("%s%s", "fid", $hmm2exon_map_A[$h]+1));
      }
      if(! $do_nomdlb) { 
        printf(" %3s", sprintf("%s%s", "md", $hmm2exon_map_A[$h]+1));
      }
      if($hmm_is_final_A[$h]) { 
        printf(" %6s", "length");
        if(! $do_noss3) { 
          printf(" %3s", "SS3");
        }
        if(! $do_nostop) { 
          printf(" %3s", "stp");
        }
        printf(" %2s", "PF");
      }
    }
    printf("  %6s", "totlen");
    printf("  %5s", "avgid");    
    if(! $do_noexist) { 
      printf("  %5s  %5s  %5s", "cds", "exons", "match");
    }
    if(! $do_noolap) { 
      printf("  %20s", " overlaps?");
    }

    printf("  %-*s", $width_result, "result");
    print "\n";
    
    # line 5 of column headers
    printf("%-20s  %6s", "#-------------------", "------");
    if(defined $origin_seq) {
      printf(" %2s %5s %5s %5s %2s", "--", "-----", "-----", "-----", "--");
    }
    for(my $h = 0; $h < $nhmm; $h++) { 
      printf("  %8s %8s", "--------", "--------");
      if(! $do_nofid) { 
        printf(" %5s", "-----");
      }
      if(! $do_nomdlb) { 
        printf(" %3s", "---");
      }
      if($hmm_is_final_A[$h]) { 
        printf(" %6s", "------");
        if(! $do_noss3) { 
          printf(" %3s", "---");
        }
        if(! $do_nostop) { 
          printf(" %3s", "---");
        }
        printf(" --");
      }
    }
    printf("  %6s", "------");
    printf("  %5s", "-----");

    if(! $do_noexist) { 
      printf("  %5s  %5s  %5s", "-----", "-----", "-----");
    }
    if(! $do_noolap) { 
      printf("  %20s", monocharacterString(20, "-"));
    }
    printf("  %-*s", $width_result, monocharacterString($width_result, "-"));

    print "\n";
  }
  ###########################################################

  #########################################################################
  # Create the initial portion of the output line, the accession and length
  printf("%-20s  %6d ", $accn, $totlen_H{$accn});
  #########################################################################

  #########################################################
  # Get information on the actual annotation of this genome
  #########################################################
  my @act_exon_starts_AA = (); # [0..$ncds-1][0..$nexons-1] start positions of actual annotations of exons for this accn, $nexons is CDS specific
  my @act_exon_stops_AA  = (); # [0..$ncds-1][0..$nexons-1] stop  positions of actual annotations of exons for this accn, $nexons is CDS specific
  my $tot_nexons = 0;
  if(exists ($cds_tbl_HHA{$accn})) { 
    ($ncds, $npos, $nneg, $nunc, $nbth, $strand_str) = getStrandStats(\%cds_tbl_HHA, $accn);
    my @cds_len_A = ();
    my @cds_coords_A = ();
    my @cds_product_A = ();
    getLengthStatsAndCoordStrings(\%cds_tbl_HHA, $accn, \@cds_len_A, \@cds_coords_A);
    getQualifierValues(\%cds_tbl_HHA, $accn, "product", \@cds_product_A);
    for(my $i = 0; $i < $ncds; $i++) { 
      # determine start and stop positions of all exons
      my @starts_A = ();
      my @stops_A  = ();
      my $nexons   = 0;
      @{$act_exon_starts_AA[$i]} = ();
      @{$act_exon_stops_AA[$i]}  = ();
      startStopsFromCoords($cds_coords_A[$i], \@starts_A, \@stops_A, \$nexons);

      my $strand = substr($strand_str, $i, 1);
      if($strand eq "-") { # switch order of starts and stops, because 1st exon is really last and vice versa
        @starts_A = reverse @starts_A;           # exons will be in reverse order, b/c we're on the negative strand
        @stops_A  = reverse @stops_A;            # exons will be in reverse order, b/c we're on the negative strand
        @{$act_exon_starts_AA[$i]} = @stops_A;  # save stops  to starts array b/c we're on the negative strand
        @{$act_exon_stops_AA[$i]}  = @starts_A; # save starts to stops  array b/c we're on the negative strand
      }
      else { 
        @{$act_exon_starts_AA[$i]} = @starts_A;
        @{$act_exon_stops_AA[$i]}  = @stops_A;
      }
      $tot_nexons += $nexons;
    }

    # printf("\n");
    # printf("$accn\n");
    # for(my $zz = 0; $zz < scalar(@act_exon_starts_AA); $zz++) { 
    #  for(my $zzz = 0; $zzz < scalar(@{$act_exon_starts_AA[$zz]}); $zzz++) { 
    #    printf("act_exon_AA[$zz][$zzz]: $act_exon_starts_AA[$zz][$zzz]  $act_exon_stops_AA[$zz][$zzz]\n");
    #  }
    #  printf("\n");
    #}
    #printf("\n");
  }
  else { 
    $ncds       = 0;
    $tot_nexons = 0;
  }

  ############################################################
  # Create the predicted annotation portion of the output line
  my $predicted_string = "";
  my $nmatch_boundaries = 0;
  my $start_codon_posn;
  my $stop_codon_posn;
  my $start_codon;
  my $stop_codon;
  my $start_codon_char;
  my $stop_codon_char;
  my $multiple_of_3_char;
  my $ss3_yes_char = ".";
  my $ss3_no_char  = "!";
  my $hit_length;
  my $at_least_one_fail; # set to '1' for each CDS if any of the 'tests' for that CDS fail
  my $pass_fail_char; # "P" or "F"
  my $pass_fail_str;  # string of pass_fail_chars

  # data structures we use for checking for overlapping annotation
  my @ol_name_A   = ();  # [0..$nhmm-1]: name of CDS/exons to print if/when outputting information on overlaps
  my @ol_start_A  = ();  # [0..$nhmm-1]: start  position of CDS/exon for use when checking for overlaps
  my @ol_stop_A   = ();  # [0..$nhmm-1]: stop   position of CDS/exon for use when checking for overlaps
  my @ol_strand_A = ();  # [0..$nhmm-1]: strand position of CDS/exon for use when checking for overlaps
 
  ###############################################################
  # create the origin sequence portion of the output line, if nec
  my $oseq_string = "";
  if(defined $origin_seq) { 
    my $norigin = (exists $origin_coords_HA{$accn}) ? scalar(@{$origin_coords_HA{$accn}}) : 0;;
    if($norigin == 1) { 
      my ($ostart, $ostop) = split(":", $origin_coords_HA{$accn}[0]);
      my $predicted_offset = ($ostart < 0) ? ($ostart + $origin_offset) : ($ostart + $origin_offset - 1);
      # $predicted_offset is now number of nts to shift origin in counterclockwise direction
      if($predicted_offset > ($totlen_H{$accn} / 2)) { # simpler (shorter distance) to move origin clockwise
        $predicted_offset = ($totlen_H{$accn} - $predicted_offset + 1);
      }
      else { # simpler to shift origin in counterclockwise direction, we denote this as a negative offset
        $predicted_offset *= -1;
      }
      $pass_fail_char = "P";
      $oseq_string .= sprintf("%2d %5d %5d %5d  %s  ", 1, $ostart, $ostop, $predicted_offset, "P");
    }
    else { 
      $pass_fail_char = "F";
      $oseq_string .= sprintf("%2d %5s %5s %5s  %s  ", $norigin, "-", "-", "-", "F");
    }
    $pass_fail_str .= $pass_fail_char;
  }
  print $oseq_string;
  ###############################################################

  # now the per-exon predictions:
  my $tot_fid = 0.; # all fractional identities added together
  my $n_fid = 0;    # number of fractional identities

  for(my $h = 0; $h < $nhmm; $h++) { 
    my $model  = $model_A[$h];
    my $cds_i  = $hmm2cds_map_A[$h];
    my $exon_i = $hmm2exon_map_A[$h];

    if($hmm_is_first_A[$h]) {
      # reset these
      $hit_length = 0; 
      $at_least_one_fail = 0;
    }

    if($predicted_string ne "") { $predicted_string .= "  "; }
    if(exists $p_start_HH{$model}{$seq_accn}) { 
      my ($start, $stop, $hangover) = ($p_start_HH{$model}{$seq_accn}, $p_stop_HH{$model}{$seq_accn}, $p_hangover_HH{$model}{$seq_accn});
      my ($hang5, $hang3) = split(":", $hangover);
      if($hang5    >  9) { $hang5 = "+"; $at_least_one_fail = 1; }
      elsif($hang5 == 0) { $hang5 = "."; }

      if($hang3       >  9) { $hang3 = "+"; $at_least_one_fail = 1; }
      elsif($hang3    == 0) { $hang3 = "."; }

      my ($start_match, $stop_match);
      ($start_match, $stop_match) = ($do_strict) ? 
          checkStrictBoundaryMatch   (\@act_exon_starts_AA, \@act_exon_stops_AA, $cds_i, $exon_i, $start, $stop) :
          checkNonStrictBoundaryMatch(\@act_exon_starts_AA, \@act_exon_stops_AA, $start, $stop);
      if($start_match) { $nmatch_boundaries++; }
      if($stop_match)  { $nmatch_boundaries++; }
 
      if($do_nobrack) { # set to '1' so brackets are never printed
        $start_match = 1;
        $stop_match  = 1; 
      }

      $hit_length += abs($stop-$start) + 1;
      if(($stop < 0 && $start > 0) || 
         ($stop > 0 && $start < 0)) { 
        # correct for off-by-one induced by the way we use negative indices distance from -1..1 is 1 nt, not 2
        $hit_length -= 1;
      }
      $predicted_string .= sprintf("%8s %8s",
                                   ($start_match ? " " . $start . " " : "[" . $start . "]"), 
                                   ($stop_match  ? " " . $stop .  " " : "[" . $stop . "]"));
      if(! $do_nofid) { 
        $predicted_string .= sprintf(" %5.3f",
                                   $p_fid2ref_HH{$model}{$seq_accn});
      }
      $tot_fid += $p_fid2ref_HH{$model}{$seq_accn};
      $n_fid++;

      if(! $do_nomdlb) { 
        $predicted_string .= "  " . $hang5 . $hang3;
      }        
                                   
      if($hmm_is_first_A[$h]) { # determine $start_codon_char
        if($p_strand_HH{$model}{$seq_accn} eq "-") { 
          $start_codon_posn = (($start-2) < 0) ? $start + $totlen_H{$accn} + 1 : $start;
        }
        else { 
          $start_codon_posn = ($start < 0) ? $start + $totlen_H{$accn} + 1 : $start;
        }
        $start_codon = fetchCodon($sqfile, $seq_accn, $start_codon_posn, $p_strand_HH{$model}{$seq_accn});
        if($start_codon eq "ATG") { 
          $start_codon_char = $ss3_yes_char;
        }
        else { 
          $start_codon_char = $ss3_no_char;
          $at_least_one_fail = 1;
        }
      }
      
      if($hmm_is_final_A[$h]) { 
        if($p_strand_HH{$model}{$seq_accn} eq "-") { 
          $stop_codon_posn    = ($stop < 0) ? ($stop + $totlen_H{$accn}) + 1 + 2 : $stop + 2;
        }
        else { 
          $stop_codon_posn    = (($stop-2) < 0) ? ($stop + $totlen_H{$accn}) + 1 - 2 : $stop - 2;
        }
        $stop_codon         = fetchCodon($sqfile, $seq_accn, $stop_codon_posn, $p_strand_HH{$model}{$seq_accn});

        if($stop_codon eq "TAG" || $stop_codon eq "TAA" || $stop_codon eq "TGA") { 
          $stop_codon_char = $ss3_yes_char;
        }
        else { 
          $stop_codon_char = $ss3_no_char;
          $at_least_one_fail = 1;
        }
        if(($hit_length % 3) == 0) { 
          $multiple_of_3_char = $ss3_yes_char;
        }
        else { 
          $multiple_of_3_char = $ss3_no_char;
          $at_least_one_fail = 1;
        }
        # append the ss3 (start/stop/multiple of 3 info)
        $predicted_string .= sprintf(" %6d", $hit_length);
        if(! $do_noss3) { 
          $predicted_string .= sprintf(" %s%s%s", $start_codon_char, $stop_codon_char, $multiple_of_3_char);
        }
        if(! $do_nostop) { 
          $predicted_string .= sprintf(" %3s", $stop_codon);
        }

        $pass_fail_char = ($at_least_one_fail) ? "F" : "P";
        $predicted_string .= sprintf(" %2s", $pass_fail_char);
        $pass_fail_str .= $pass_fail_char;
      }

      # save information for overlap check
      push(@ol_name_A, sprintf "%d.%d", $hmm2cds_map_A[$h]+1, $hmm2exon_map_A[$h]+1);
      push(@ol_start_A, $start);
      push(@ol_stop_A,  $stop);
      push(@ol_strand_A, $p_strand_HH{$model}{$seq_accn});
    }
    else { 
      # printf("no hits for $model $seq_accn\n");
      if($do_nomdlb) { 
        $width = ($hmm_is_final_A[$h]) ? 34 : 23;
        $predicted_string .= sprintf("%*s", $width, "NO PREDICTION");
      }
      else { 
        $width = ($hmm_is_final_A[$h]) ? 38 : 27;
        $predicted_string .= sprintf("%*s", $width, "NO PREDICTION");
      }
    }
  }
  print $predicted_string;

  printf("  %6d", $totlen_H{$accn});
  printf("  %5.3f", $tot_fid / $n_fid);

  # output number of actually annotated CDS and summed total of exons in those CDS, if nec
  if(! $do_noexist) { 
    printf("  %5d  %5d  %5d", $ncds, $tot_nexons, $nmatch_boundaries);
  }

  # check for overlaps
  my $overlap_notes;
  if($a == 0) { 
    # the reference, determine which overlaps are allowed, we'll fill @allowed_ol_AA in checkForOverlaps
    ($pass_fail_char, $overlap_notes) = checkForOverlaps(\@ol_name_A, \@ol_start_A, \@ol_stop_A, \@ol_strand_A, undef, \@ref_ol_AA);
  }
  else { 
    # not the reference, we'll determine if this accession 'passes' the overlap test based on whether it's observed
    # overlaps match those in \@allowed_ol_AA exactly or not
    ($pass_fail_char, $overlap_notes) = checkForOverlaps(\@ol_name_A, \@ol_start_A, \@ol_stop_A, \@ol_strand_A, \@ref_ol_AA, undef);
  }
  $pass_fail_str .= $pass_fail_char;

  # output overlap info, if nec
  if((! $do_noolap) && ($overlap_notes ne "")) { 
    printf("  %20s", $overlap_notes);
  }

  my $result_str = ($pass_fail_str =~ m/F/) ? "FAIL" : "PASS";
  $result_str .= " " . $pass_fail_str;
  printf("  %s", $result_str);

  print "\n";
}

if(! $do_noexp) { 
  printColumnHeaderExplanations((defined $origin_seq), $do_nomdlb, $do_noexist, $do_nobrack, $do_nostop, $do_nofid, $do_noss3, $do_noolap);
}

#############
# SUBROUTINES
#############
# Subroutine: runCommand()
# Args:       $cmd:            command to run, with a "system" command;
#             $be_verbose:     '1' to output command to stdout before we run it, '0' not to
#
# Returns:    amount of time the command took, in seconds
# Dies:       if $cmd fails

sub runCommand {
  my $sub_name = "runCommand()";
  my $nargs_exp = 2;

  my ($cmd, $be_verbose) = @_;

  if($be_verbose) { 
    print ("Running cmd: $cmd\n"); 
  }

  my ($seconds, $microseconds) = gettimeofday();
  my $start_time = ($seconds + ($microseconds / 1000000.));
  system($cmd);
  ($seconds, $microseconds) = gettimeofday();
  my $stop_time = ($seconds + ($microseconds / 1000000.));

  if($? != 0) { die "ERROR command failed:\n$cmd\n"; }

  return ($stop_time - $start_time);
}

# Subroutine: parseLength()
# Synopsis:   Parses a length file and stores the lengths read
#             into %{$len_HR}.
# Args:       $lenfile: full path to a length file
#             $len_HR:  ref to hash of lengths, key is accession
#
# Returns:    void; fills %{$len_HR}
#
# Dies:       if problem parsing $lenfile

sub parseLength {
  my $sub_name = "parseLength()";
  my $nargs_exp = 2;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($lenfile, $len_HR) = @_;

#HM448898.1	2751

  open(LEN, $lenfile) || die "ERROR unable to open $lenfile for reading";

  while(my $line = <LEN>) { 
    chomp $line;
    my ($accn, $length) = split(/\s+/, $line);
    if($length !~ m/^\d+$/) { die "ERROR couldn't parse length file line: $line\n"; } 

    stripVersion(\$accn);
    $len_HR->{$accn} = $length;
  }
  close(LEN);

  return;
}

# Subroutine: parseTable()
# Synopsis:   Parses a table file and stores the relevant info in it 
#             into $values_HAR.
# Args:       $tblfile:      full path to a table file
#             $values_HHAR:  ref to hash of hash of arrays
#
# Returns:    void; fills @{$values_HHAR}
#
# Dies:       if problem parsing $tblfile

sub parseTable {
  my $sub_name = "parseTable()";
  my $nargs_exp = 2;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($tblfile, $values_HHAR) = @_;

##full-accession	accession	coords	strand	min-coord	gene
#gb|HM448898.1|	HM448898.1	129..476	+	129	AV2

  open(TBL, $tblfile) || die "ERROR unable to open $tblfile for reading";

  # get column header line:
  my $line_ctr = 0;
  my @colnames_A = ();
  my $line = <TBL>;
  my $ncols = undef;
  $line_ctr++;
  if(! defined $line) { die "ERROR did not read any lines from file $tblfile"; }
  chomp $line;
  if($line =~ s/^\#//) { 
    @colnames_A = split(/\t/, $line);
    $ncols = scalar(@colnames_A);
  }
  else { 
    die "ERROR first line of $tblfile did not start with \"#\"";
  }
  if($colnames_A[0] ne "full-accession") { die "ERROR first column name is not full-accession"; }
  if($colnames_A[1] ne "accession")      { die "ERROR second column name is not accession"; }
  if($colnames_A[2] ne "coords")         { die "ERROR third column name is not coords"; }

  # read remaining lines
  while($line = <TBL>) { 
    chomp $line;
    $line_ctr++;
    if($line =~ m/^\#/) { die "ERROR, line $line_ctr of $tblfile begins with \"#\""; }
    my @el_A = split(/\t/, $line);
    if(scalar(@el_A) != $ncols) { 
      die "ERROR, read wrong number of columns in line $line_ctr of file $tblfile";
    }
    my $prv_min_coord = 0;
    # get accession
    my $accn = $el_A[1]; 
    stripVersion(\$accn);
    if(! exists $values_HHAR->{$accn}) { 
      %{$values_HHAR->{$accn}} = (); 
    }

    for(my $i = 0; $i < $ncols; $i++) { 
      my $colname = $colnames_A[$i];
      my $value   = $el_A[$i];
      if($colname eq "min-coord") { 
        if($value < $prv_min_coord) { 
          die "ERROR, minimum coordinates out of order at line $line_ctr and previous line of file $tblfile"; 
        }
        $prv_min_coord = $value; 
        # printf("prv_min_coord: $prv_min_coord\n");
      }

      if(! exists $values_HHAR->{$accn}{$colname}) { 
        @{$values_HHAR->{$accn}{$colname}} = ();
      }
      push(@{$values_HHAR->{$accn}{$colname}}, $el_A[$i]);
      #printf("pushed $accn $colname $el_A[$i]\n");
    }
  }
  close(TBL);
  return;
}

# Subroutine: getStrandStats()
# Synopsis:   Retreive strand stats.
# Args:       $tbl_HHAR:  ref to hash of hash of arrays
#             $accn:      1D key to print for
#
# Returns:    6 values:
#             $nfeatures:  number of features
#             $npos:       number of genes with all segments on positive strand
#             $nneg:       number of genes with all segmenst on negative strand
#             $nunc:       number of genes with all segments on unknown strand 
#             $nbth:       number of genes with that don't fit above 3 categories
#             $strand_str: strand string, summarizing strand of all genes, in order
#
sub getStrandStats {
  my $sub_name = "getStrandStats()";
  my $nargs_exp = 2;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
 
  my ($tbl_HHAR, $accn) = @_;

  my $nfeatures; # number of genes in this genome
  my $npos = 0;  # number of genes on positive strand 
  my $nneg = 0;  # number of genes on negative strand 
  my $nbth = 0;  # number of genes with >= 1 segment on both strands (usually 0)
  my $nunc = 0;  # number of genes with >= 1 segments that are uncertain (usually 0)
  my $strand_str = "";

  if(! exists $tbl_HHAR->{$accn}{"strand"}) { die("ERROR didn't read strand information for accn: $accn\n"); }

  $nfeatures = scalar(@{$tbl_HHAR->{$accn}{"accession"}});
  if ($nfeatures > 0) { 
    for(my $i = 0; $i < $nfeatures; $i++) { 

      # sanity check
      my $accn2 = $tbl_HHAR->{$accn}{"accession"}[$i];
      stripVersion(\$accn2);
      if($accn ne $accn2) { die "ERROR accession mismatch in gene ftable file ($accn ne $accn2)"; }

      if   ($tbl_HHAR->{$accn}{"strand"}[$i] eq "+") { $npos++; }
      elsif($tbl_HHAR->{$accn}{"strand"}[$i] eq "-") { $nneg++; }
      elsif($tbl_HHAR->{$accn}{"strand"}[$i] eq "!") { $nbth++; }
      elsif($tbl_HHAR->{$accn}{"strand"}[$i] eq "?") { $nunc++; }
      else { die("ERROR unable to parse strand for feature %d for $accn\n", $i+1); }
      $strand_str .= $tbl_HHAR->{$accn}{"strand"}[$i];
    }
  }

  return ($nfeatures, $npos, $nneg, $nunc, $nbth, $strand_str);
}


# Subroutine: getLengthStatsAndCoordStrings()
# Synopsis:   Retreive length stats for an accession
#             the length of all annotated genes.
# Args:       $tbl_HHAR:  ref to hash of hash of arrays
#             $accn:      accession we're interested in
#             $len_AR:    ref to array to fill with lengths of features in %{$tbl_HAR}
#             $coords_AR: ref to array to fill with coordinates for each gene
# Returns:    void; fills @{$len_AR} and @{$coords_AR}
#
sub getLengthStatsAndCoordStrings { 
  my $sub_name = "getLengthStatsAndCoordStrings()";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
 
  my ($tbl_HHAR, $accn, $len_AR, $coords_AR) = @_;

  if(! exists $tbl_HHAR->{$accn}) { die "ERROR in $sub_name, no data for accession: $accn"; }
  if(! exists $tbl_HHAR->{$accn}{"coords"}) { die "ERROR in $sub_name, no coords data for accession: $accn"; }

  my $ngenes = scalar(@{$tbl_HHAR->{$accn}{"coords"}});

  if ($ngenes > 0) { 
    for(my $i = 0; $i < $ngenes; $i++) { 
      push(@{$len_AR},    lengthFromCoords($tbl_HHAR->{$accn}{"coords"}[$i]));
      push(@{$coords_AR}, $tbl_HHAR->{$accn}{"coords"}[$i]);
      #push(@{$coords_AR}, addAccnToCoords($tbl_HHAR->{$accn}{"coords"}[$i], $accn));
    }
  }

  return;
}

# Subroutine: getQualifierValues()
# Synopsis:   Retreive values for the qualifier $qualifier in the given %tbl_HHAR
#             and return the values in $values_AR.
#             the length of all annotated genes.
# Args:       $tbl_HHAR:  ref to hash of hash of arrays
#             $accn:      accession we're interested in
#             $qualifier: qualifier we're interested in (e.g. 'Product')
#             $values_AR: ref to array to fill with values of $qualifier
# Returns:    void; fills @{$values_AR}
#
sub getQualifierValues {
  my $sub_name = "getQualifierValues()";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
 
  my ($tbl_HHAR, $accn, $qualifier, $values_AR) = @_;

  if(! exists $tbl_HHAR->{$accn}) { die "ERROR in $sub_name, no data for accession: $accn"; }

  if(! exists $tbl_HHAR->{$accn}{$qualifier}) { return; } # no annotation for $qualifier, do not update arrays

  my $nvalues = scalar(@{$tbl_HHAR->{$accn}{$qualifier}});

  if ($nvalues > 0) { 
    for(my $i = 0; $i < $nvalues; $i++) { 
      push(@{$values_AR},  $tbl_HHAR->{$accn}{$qualifier}[$i]);
    }
  }

  return;
}


# Subroutine: addAccnToCoords()
# Synopsis:   Add accession Determine the length of a region give its coords in NCBI format.
#
# Args:       $coords:  the coords string
#             $accn:    accession to add
# Returns:    The accession to add to the coords string.
#
sub addAccnToCoords { 
  my $sub_name = "addAccnToCoords()";
  my $nargs_exp = 2;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
  
  my ($coords, $accn) = @_;

  my $ret_coords = $coords;
  # deal with simple case of \d+..\d+
  if($ret_coords =~ /^\<?\d+\.\.\>?\d+/) { 
    $ret_coords = $accn . ":" . $ret_coords;
  }
  # replace 'complement(\d' with 'complement($accn:\d+'
  while($ret_coords =~ /complement\(\<?\d+/) { 
    $ret_coords =~ s/complement\((\<?\d+)/complement\($accn:$1/;
  }
  # replace 'join(\d' with 'join($accn:\d+'
  while($ret_coords =~ /join\(\<?\d+/) { 
    $ret_coords =~ s/join\((\<?\d+)/join\($accn:$1/;
  }
  # replace ',\d+' with ',$accn:\d+'
  while($ret_coords =~ /\,\s*\<?\d+/) { 
    $ret_coords =~ s/\,\s*(\<?\d+)/\,$accn:$1/;
  }

  #print("addAccnToCoords(), input $coords, returning $ret_coords\n");
  return $ret_coords;
}

# Subroutine: stripVersion()
# Purpose:    Given a ref to an accession.version string, remove the version.
# Args:       $accver_R: ref to accession version string
# Returns:    Nothing, $$accver_R has version removed
sub stripVersion {
  my $sub_name  = "stripVersion()";
  my $nargs_exp = 1;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
  
  my ($accver_R) = (@_);

  $$accver_R =~ s/\.[0-9]*$//; # strip version

  return;
}

# Subroutine: stripPath()
# Purpose:    Given a file path, remove the all directories and leave only the file name.
# Args:       $filename: full path to file
# Returns:    only the file name, without any directory structure
sub stripPath {
  my $sub_name  = "stripPath()";
  my $nargs_exp = 1;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
  
  my ($filename) = (@_);

  $filename =~ s/^.+\///;

  return $filename;
}


# Subroutine: validateRefCDSAreUnique()
# Purpose:    Validate that all CDS:product annotation for all reference CDS 
#             are unique, i.e. there are no two CDS that have the same value
#             in their CDS:product annotation.
# Args:       $ref_ncds:           number of reference CDS
#             $ref_cds_product_AR: ref to array of CDS:product annotations for the $ref_ncds reference CDS 
# Returns:    void
# Dies:       if more than one ref CDS have same CDS:product annotation.
sub validateRefCDSAreUnique {
  my $sub_name  = "validateRefCDSAreUnique()";
  my $nargs_exp = 2;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
  
  my ($ref_ncds, $ref_cds_product_AR) = @_;

  my %exists_H = ();
  for(my $i = 0; $i < $ref_ncds; $i++) { 
    if(exists $exists_H{$ref_cds_product_AR->[$i]}) { die sprintf("ERROR %s is CDS:product value for more than one reference CDS!", $ref_cds_product_AR->[$i]); }
  }

  return;
}

# Subroutine: startStopsFromCoords()
# Synopsis:   Extract the starts and stops from a coords string.
#
# Args:       $coords:  the coords string
#             $starts_AR: ref to array to fill with start positions
#             $stops_AR:  ref to array to fill with stop positions
#             $nexons_R:  ref to scalar that fill with the number of exons
#
# Returns:    void; but fills
#
sub startStopsFromCoords { 
  my $sub_name = "startStopsFromCoords()";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
 
  my ($coords, $starts_AR, $stops_AR, $nexons_R) = @_;

  @{$starts_AR} = ();
  @{$stops_AR}  = ();
  $$nexons_R    = 0;
  
  my $orig_coords = $coords;
  # Examples:
  # complement(2173412..2176090)
  # complement(join(226623..226774, 226854..229725))

  # remove 'complement('  ')'
  $coords =~ s/^complement\(//;
  $coords =~ s/\)$//;

  # remove 'join('  ')'
  $coords =~ s/^join\(//;
  $coords =~ s/\)$//;

  my @el_A = split(/\s*\,\s*/, $coords);

  my $length = 0;
  foreach my $el (@el_A) { 
    # rare case: remove 'complement(' ')' that still exists:
    $el =~ s/^complement\(//;
    $el =~ s/\)$//;
    $el =~ s/\<//; # remove '<'
    $el =~ s/\>//; # remove '>'
    if($el =~ m/^(\d+)\.\.(\d+)$/) { 
      push(@{$starts_AR}, $1);
      push(@{$stops_AR},  $2);
      $$nexons_R++;
    }
    else { 
      die "ERROR unable to parse $orig_coords in $sub_name"; 
    }
  }

  # printf("in startStopsFromCoords(): orig_coords: $orig_coords returning length: $length\n");
  return;
}

# Subroutine: lengthFromCoords()
# Synopsis:   Determine the length of a region give its coords in NCBI format.
#
# Args:       $coords:  the coords string
#
# Returns:    length in nucleotides implied by $coords  
#
sub lengthFromCoords { 
  my $sub_name = "lengthFromCoords()";
  my $nargs_exp = 1;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
 
  my ($coords) = @_;

  my @starts_A = ();
  my @stops_A  = ();
  my $nexons   = 0;

  startStopsFromCoords($coords, \@starts_A, \@stops_A, \$nexons);

  my $length = 0;
  for(my $i = 0; $i < $nexons; $i++) { 
    $length += abs($starts_A[$i] - $stops_A[$i]) + 1;
  }

  return $length;
}

# Subroutine: createHmmDb()
# Synopsis:   Create an HMM Db from a stockholm database file.
#
# Args:       $hmmbuild:   path to 'hmmbuild' executable
#             $hmmpress:   path to 'hmmpress' executable
#             $stk_file:   stockholm DB file
#             $out_root:   string for naming output files
#
# Returns:    void
#
sub createHmmDb { 
  my $sub_name = "createHmmDb()";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($hmmbuild, $hmmpress, $stk_file, $out_root) = @_;

  if(! -s $stk_file)  { die "ERROR in $sub_name, $stk_file file does not exist or is empty"; }

  # remove the binary files, possibly from an earlier hmmbuild/hmmpress:
  for my $suffix ("h3f", "h3i", "h3m", "h3p") { 
    my $file = $out_root . ".hmm." . $suffix;
    if(-e $file) { unlink $file; }
  }

  # first build the models

  printf("%-50s ... ", "# Running hmmbuild");
  my $cmd = "$hmmbuild --dna $out_root.hmm $stk_file > $out_root.hmmbuild";
  my $secs_elapsed = runCommand($cmd, 0);
#  printf("done. [$out_root.nhmmer and $out_root.tblout]\n");
  printf("done. [%.1f seconds]\n", $secs_elapsed);

  # next, press the HMM DB we just created
  printf("%-50s ... ", "# Running hmmpress");
  $cmd = "$hmmpress $out_root.hmm > $out_root.hmmpress";
  $secs_elapsed = runCommand($cmd, 0);
#  printf("done. [$out_root.nhmmer and $out_root.tblout]\n");
  printf("done. [%.1f seconds]\n", $secs_elapsed);

  return;
}

# Subroutine: createCmDb()
# Synopsis:   Create an CM database from a stockholm database file
#             for use with Infernal 1.1.
#             the $cmbuild executable. If $cmcalibrate is defined
#             also run cmcalibrate. 
#
# Args:       $cmbuild:          path to 'cmbuild' executable
#             $cmcalibrate:      path to 'cmcalibrate' executable
#             $cmpress:          path to 'cmpress' executable
#             $do_calib_slow:    '1' to calibrate using default parameters instead of
#                                options to make it go much faster
#             $do_calib_cluster: '1' to submit calibration job to cluster, '0' to do it locally
#             $stk_file:         stockholm DB file
#             $out_root:         string for naming output files
#
# Returns:    void
#
sub createCmDb { 
  my $sub_name = "createCmDb()";
  my $nargs_exp = 7;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($cmbuild, $cmcalibrate, $cmpress, $do_calib_slow, $do_calib_cluster, $stk_file, $out_root) = @_;

  if(! -s $stk_file)  { die "ERROR in $sub_name, $stk_file file does not exist or is empty"; }

  # remove the binary files, possibly from an earlier cmbuild/cmpress:
  for my $suffix ("i1m", "i1i", "i1f", "i1p") { 
    my $file = $out_root . ".cm." . $suffix;
    if(-e $file) { unlink $file; }
  }

  my ($cmbuild_opts,     $cmbuild_cmd);
  my ($cmcalibrate_opts, $cmcalibrate_cmd);
  my ($cmpress_opts,     $cmpress_cmd);

  $cmbuild_opts = "-F";
  $cmbuild_cmd  = "$cmbuild $cmbuild_opts $out_root.cm $stk_file > $out_root.cmbuild";

  $cmcalibrate_opts = " --cpu 4 ";
  if(! $do_calib_slow) { $cmcalibrate_opts .= " -L 0.04 "; }
  $cmcalibrate_cmd  = "$cmcalibrate $cmcalibrate_opts $out_root.cm > $out_root.cmcalibrate";
  
  $cmpress_cmd = "$cmpress $out_root.cm > $out_root.cmpress";

  # first build the models
  printf("%-50s ... ", "# Running cmbuild");
  my $secs_elapsed = runCommand($cmbuild_cmd, 0);
  printf("done. [%.1f seconds]\n", $secs_elapsed);

  if($do_calib_cluster) { 
    # submit a job to the cluster and exit. 
    my $out_tail = $out_root;
    $out_tail =~ s/^.+\///;
    my $jobname = "cp." . $out_tail;
    my $errfile = $out_root . ".err";
    my $cluster_cmd = "qsub -N $jobname -b y -v SGE_FACILITIES -P unified -S /bin/bash -cwd -V -j n -o /dev/null -e $errfile -m n -l h_rt=288000,h_vmem=8G,mem_free=8G -pe multicore 4 -R y " . "\"" . $cmcalibrate_cmd . ";" . $cmpress_cmd . ";\"\n";
    # print("$cluster_cmd\n");
    runCommand($cluster_cmd, 0);
  }
  else { 
    # calibrate the model
    printf("%-50s ... ", "# Running cmcalibrate");
    $secs_elapsed = runCommand($cmcalibrate_cmd, 0);
    #printf("\n$cmcalibrate_cmd\n");
    printf("done. [%.1f seconds]\n", $secs_elapsed);

    # press the model
    printf("%-50s ... ", "# Running cmpress");
    $secs_elapsed = runCommand($cmpress_cmd, 0);
    #printf("\n$cmpress_cmd\n");
    printf("done [%.1f seconds]\n", $secs_elapsed);
  } # end of 'else' entered if $do_calib_cluster is false

  return;
}

# Subroutine: runNhmmscan()
# Synopsis:   Perform a homology search using nhmmscan.
#
# Args:       $nhmmscan:     path to nhmmscan executable
#             $model_db:     path to model HMM database
#             $seq_fasta:    path to seq fasta file
#             $tblout_file:  path to --tblout output file to create, undef to not create one
#             $stdout_file:  path to output file to create with standard output from nhmmscan, undef 
#                            to pipe to /dev/null
#
# Returns:    void
#
sub runNhmmscan { 
  my $sub_name = "runNhmmscan()";
  my $nargs_exp = 5;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

 
  my ($nhmmscan, $model_db, $seq_fasta, $tblout_file, $stdout_file) = @_;

  # my $opts = " --noali --tblout $tblout_file ";
  my $opts = " --tblout $tblout_file ";

  if(! defined $stdout_file) { $stdout_file = "/dev/null"; }

  if(! -s $model_db)  { die "ERROR in $sub_name, $model_db file does not exist or is empty"; }
  if(! -s $seq_fasta) { die "ERROR in $sub_name, $seq_fasta file does not exist or is empty"; }

  printf("%-50s ... ", "# Running nhmmscan");
  my $cmd = "$nhmmscan $opts $model_db $seq_fasta > $stdout_file";
  my $secs_elapsed = runCommand($cmd, 0);
  printf("done. [%.1f seconds]\n", $secs_elapsed);

  return;
}

# Subroutine: runCmscan()
# Synopsis:   Run Infernal 1.1's cmscan.
#
# Args:       $cmscan:      path to cmscan executable
#             $do_glocal:   '1' to use the -g option, '0' not to
#             $model_db:    path to model CM database
#             $seq_fasta:   path to seq fasta file
#             $tblout_file: path to --tblout output file to create, undef to not create one
#             $stdout_file: path to output file to create with standard output from cmsearch, undef 
#                           to pipe to /dev/null
#
# Returns:    void
#
sub runCmscan { 
  my $sub_name = "runCmscan()";
  my $nargs_exp = 6;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($cmscan, $do_glocal, $model_db, $seq_fasta, $tblout_file, $stdout_file) = @_;

  my $opts = "";
  if($do_iglocal) { $opts .= "-g "; }
  $opts .= " --cpu 0 --rfam --tblout $tblout_file --verbose --nohmmonly ";
  if(! defined $stdout_file) { $stdout_file = "/dev/null"; }

  if(! -s $model_db)   { die "ERROR in $sub_name, $model_db file does not exist or is empty"; }
  if(! -s $seq_fasta) { die "ERROR in $sub_name, $seq_fasta file does not exist or is empty"; }

  printf("%-50s ... ", "# Running cmscan");
  my $cmd = "$cmscan $opts $model_db $seq_fasta > $stdout_file";
  $secs_elapsed = runCommand($cmd, 0);
  printf("done. [%.1f seconds]\n", $secs_elapsed);

  return;
}

# Subroutine: annotateStockholmAlignment
#
# Synopsis:   Read in a stockholm alignment ($in_file), and 
#             add a name ($name) to it, then optionally add
#             a blank SS (#=GC SS_cons) annotation to it
#             and output a new file ($out_file) that is
#             identical to it but with the name annotation
#             and possibly a blank SS.
#
# Args:       $name:          name to add to alignment
#             $do_blank_ss:   '1' to add a blank SS, else '0'
#             $in_file:       input stockholm alignment
#             $out_file:      output stockholm alignment to create
#
# Returns:    alignment length
#
sub annotateStockholmAlignment {
  my $sub_name = "annotateStockholmAlignment";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($name, $do_blank_ss, $in_file, $out_file) = @_;

  # printf("# Naming alignment in $in_file to $name ... "); 

  # open and validate file
  my $msa = Bio::Easel::MSA->new({
    fileLocation => $in_file,
                                 });  
  $msa->set_name($name);
  if($do_blank_ss) { 
    $msa->set_blank_ss_cons;
  }
  $msa->write_msa($out_file);

  # printf("done. [$out_file]\n");
  return $msa->alen;
}

# Subroutine: parseNhmmscanTblout
#
# Synopsis:   Parse nhmmscan tblout output into 5 2D hashes.
#             For each 2D hash first key is seq name, second key
#             is model name, value is either start, stop, strand,
#             score or hangover (number of model positions not included
#             on 5' and 3' end). Information for the lowest E-value hit
#             for each seq/model pair is stored. This will be the
#             first hit encountered in the file for each seq/model
#             pair.
#
# Args:       $tblout_file:   tblout file to parse
#             $do_hmmenv:     '1' to use envelope boundaries, else use window boundaries
#             $totlen_HR:     ref to hash, key is accession, value is length, pre-filled
#             $start_HHR:     ref to 2D hash of start values, to fill here
#             $stop_HHR:      ref to 2D hash of stop values, to fill here
#             $strand_HHR:    ref to 2D hash of strand value, to fill here
#             $score_HHR:     ref to 2D hash of score values, to fill here
#             $hangoverHHR:   ref to 2D hash of model hangover values, to fill here
#
# Returns:    void
#
sub parseNhmmscanTblout { 
  my $sub_name = "parseNhmmscanTblout";
  my $nargs_exp = 8;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
  
  my ($tblout_file, $do_hmmenv, $totlen_HR, $start_HHR, $stop_HHR, $strand_HHR, $score_HHR, $hangover_HHR) = @_;
  
  open(IN, $tblout_file) || die "ERROR unable to open $tblout_file for reading";

  my $line_ctr = 0;
  while(my $line = <IN>) { 
    $line_ctr++;
    if($line =~ m/^\# \S/ && $line_ctr == 1) { 
      # sanity check, make sure the fields are what we expect
      chomp $line;
      if($line !~ m/#\s+target\s+name\s+accession\s+query name\s+accession\s+hmmfrom\s+hmm to\s+alifrom\s+ali to\s+envfrom  env to\s+modlen\s+strand\s+E-value\s+score\s+bias\s+description of target/) { 
        die "ERROR unexpected field names in $tblout\n$line\n";
      }
    }
    elsif($line !~ m/^\#/) { 
      chomp $line;
      #Maize-streak_r23.NC_001346/Maize-streak_r23.NC_001346.ref.cds.4        -          NC_001346:genome:NC_001346:1:2689:+: -                1     819    2 527    1709    2527    1709     819    -    9.8e-261  856.5  12.1  -
      my @elA = split(/\s+/, $line);
      my ($mdl, $seq, $hmmfrom, $hmmto, $alifrom, $alito, $envfrom, $envto, $mdllen, $strand, $score) = 
          ($elA[0], $elA[2], $elA[4], $elA[5], $elA[6], $elA[7], $elA[8], $elA[9], $elA[10], $elA[11], $elA[13]);

      my $from = ($do_hmmenv) ? $envfrom : $alifrom;
      my $to   = ($do_hmmenv) ? $envto   : $alito;

      my $accn = $seq;
      $accn =~ s/\:.+$//;
      if(! exists $totlen_HR->{$accn}) { die "ERROR unable to determine accession with stored length from fasta sequence $mdl (seq: $seq)"; }
      my $L = $totlen_HR->{$accn};

      storeHit($mdl, $seq, $mdllen, $L, $hmmfrom, $hmmto, $from, $to, $strand, $score, $start_HHR, $stop_HHR, $strand_HHR, $score_HHR, $hangover_HHR);
    }
  }
  close(IN);
  
  return;
}

# Subroutine: parseCmscanTblout
#
# Synopsis:   Parse Infernal 1.1 cmscan --tblout output.
#             For each 2D hash first key is seq name, second key
#             is model name, value is either start, stop, strand,
#             score or hangover (number of model positions not included
#             on 5' and 3' end). Information for the lowest E-value hit
#             for each seq/model pair is stored. This will be the
#             first hit encountered in the file for each seq/model
#             pair.
#
# Args:       $tblout_file:   tblout file to parse
#             $totlen_HR:     ref to hash, key is accession, value is length, pre-filled
#             $mdllen_HR:     ref to hash, key is model name, value is model length, pre-filled
#             $start_HHR:     ref to 2D hash of start values, to fill here
#             $stop_HHR:      ref to 2D hash of stop values, to fill here
#             $strand_HHR:    ref to 2D hash of strand value, to fill here
#             $score_HHR:     ref to 2D hash of score values, to fill here
#             $hangoverHHR:   ref to 2D hash of model hangover values, to fill here
#
# Returns:    void
#
sub parseCmscanTblout { 
  my $sub_name = "parseCmscanTblout";
  my $nargs_exp = 8;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }
  
  my ($tblout_file, $totlen_HR, $mdllen_HR, $start_HHR, $stop_HHR, $strand_HHR, $score_HHR, $hangover_HHR) = @_;
  
  open(IN, $tblout_file) || die "ERROR unable to open $tblout_file for reading";

  my $line_ctr = 0;
  while(my $line = <IN>) { 
    $line_ctr++;
    if($line =~ m/^\# \S/ && $line_ctr == 1) { 
      # sanity check, make sure the fields are what we expect
      chomp $line;
      if($line !~ m/#target name\s+accession\s+query name\s+accession\s+mdl\s+mdl\s+from\s+mdl to\s+seq from\s+seq to\s+strand\s+trunc\s+pass\s+gc\s+bias\s+score\s+E-value inc description of target/) { 
        die "ERROR unexpected field names in $tblout\n$line\n";
      }

    }
    elsif($line !~ m/^\#/) { 
      chomp $line;
      #Maize-streak_r23.NC_001346.ref.cds.4        -         NC_001346:genome-duplicated:NC_001346:1:2689:+:NC_001346:1:2689:+: -          cm        1      819     2527     1709      -    no    1 0.44   0.2  892.0         0 !   -
      my @elA = split(/\s+/, $line);
      my ($mdl, $seq, $mod, $mdlfrom, $mdlto, $from, $to, $strand, $score) = 
          ($elA[0], $elA[2], $elA[4], $elA[5], $elA[6], $elA[7], $elA[8], $elA[9], $elA[14]);

      my $accn = $seq;
      $accn =~ s/\:.+$//;
      if(! exists $totlen_HR->{$accn})  { die "ERROR unable to determine accession with stored length from fasta sequence $mdl"; }
      if(! exists $mdllen_HR->{$mdl})   { die "ERROR do not have model length information for model $mdl"; }
      my $L      = $totlen_HR->{$accn};
      my $mdllen = $mdllen_HR->{$mdl};

      storeHit($mdl, $seq, $mdllen, $L, $mdlfrom, $mdlto, $from, $to, $strand, $score, $start_HHR, $stop_HHR, $strand_HHR, $score_HHR, $hangover_HHR);
    }
  }
  close(IN);
  
  return;
}

# Subroutine: storeHit
#
# Synopsis:   Helper function for parseNhmmscanTblout and parseCmscanTblout.
#             Given info on a hit and refs to hashes to store info on it in,
#             store it.
#
# Args:       $mdl:           model name
#             $seq:           sequence name
#             $mdllen:        model length
#             $L:             target sequence length
#             $mdlfrom:       start position of hit
#             $mdlto:         stop position of hit
#             $seqfrom:       start position of hit
#             $seqto:         stop position of hit
#             $strand:        strand of hit
#             $score:         bit score of hit
#             $start_HHR:     ref to 2D hash of start values, to fill here
#             $stop_HHR:      ref to 2D hash of stop values, to fill here
#             $strand_HHR:    ref to 2D hash of strand value, to fill here
#             $score_HHR:     ref to 2D hash of score values, to fill here
#             $hangover_HHR:  ref to 2D hash of model hangover values, to fill here
#                             start..stop coordinates for $qseq.
# Returns:    void
#
sub storeHit { 
  my $sub_name = "storeHit";
  my $nargs_exp = 15;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($mdl, $seq, $mdllen, $L, $mdlfrom, $mdlto, $seqfrom, $seqto, $strand, $score, 
      $start_HHR, $stop_HHR, $strand_HHR, $score_HHR, $hangover_HHR) = @_;

  # only consider hits where either the start or end are less than the total length
  # of the genome. Since we typically duplicate all genomes, this avoids storing 
  # duplicate hits at different positions.
  if(($seqfrom <= $L) || ($seqto <= $L)) { 
    
    # deal with case where one but not both of from to is > L:
    if($seqfrom > $L || $seqto > $L) { 
      $seqfrom -= $L; 
      $seqto   -= $L; 
      if($seqfrom < 0)  { $seqfrom--; }
      if($seqto   < 0)  { $seqto--; }
    }
    
    if(! exists $start_HHR->{$mdl}) { # initialize
      %{$start_HHR->{$mdl}}    = ();
      %{$stop_HHR->{$mdl}}     = ();
      %{$strand_HHR->{$mdl}}   = ();
      %{$score_HHR->{$mdl}}    = ();
      %{$hangover_HHR->{$mdl}} = ();
    }
    if(! exists $start_HHR->{$mdl}{$seq})    { $start_HHR->{$mdl}{$seq}    = $seqfrom; }
    if(! exists $stop_HHR->{$mdl}{$seq})     { $stop_HHR->{$mdl}{$seq}     = $seqto; }
    if(! exists $strand_HHR->{$mdl}{$seq})   { $strand_HHR->{$mdl}{$seq}   = $strand; }
    if(! exists $score_HHR->{$mdl}{$seq})    { $score_HHR->{$mdl}{$seq}    = $score; }
    if(! exists $hangover_HHR->{$mdl}{$seq}) { $hangover_HHR->{$mdl}{$seq} = ($mdlfrom - 1) . ":" . ($mdllen - $mdlto); }
  }

  return;
}

# Subroutine: findSeqInFile
#
# Synopsis:   Identify all exact occurences of a sequence in a file
#             of sequences, and store the coordinates of the
#             matches in %{$coords_HAR}.
#
# Args:       $sqfile:        Bio::Easel::SqFile object, the sequence file to search in
#             $qseq:          query sequence we're looking for
#             $do_nodup:      '1' if -nodup was used at command line, else '0'
#             $coords_HAR:    ref to hash of arrays to store coords in
#                             key is accession, value is array of 
#                             start..stop coordinates for $qseq.
# Returns:    void
#
sub findSeqInFile { 
  my $sub_name = "findSeqInFile";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($sqfile, $qseq, $do_nodup, $coords_HAR) = @_;

  # printf("# Naming alignment in $in_file to $name ... "); 

  # fetch each sequence and look for $qseq in it
  # (could (and probably should) make this more efficient...)
  my $nseq = $sqfile->nseq_ssi();
  for(my $i = 0; $i < $nseq; $i++) { 
    my $seqname   = $sqfile->fetch_seq_name_given_ssi_number($i);
    my $accn      = $seqname;
    # example: AJ224507:genome-duplicated:AJ224507:1:2685:+:AJ224507:1:2685:+:
    $accn =~ s/\:.+$//;
    my $fasta_seq = $sqfile->fetch_seq_to_fasta_string($seqname, -1);
    my ($header, $seq) = split(/\n/, $fasta_seq);
    chomp $seq;
    my $L = ($do_nodup) ? length($seq) : (length($seq) / 2);
    # now use Perl's index() function to find all occurrences of $qseq
    my $qseq_posn = index($seq, $qseq);
    while($qseq_posn != -1) { 
      $qseq_posn++;
      if($qseq_posn <= $L) { 
        my $qseq_start = $qseq_posn;
        my $qseq_stop  = $qseq_posn + length($qseq) - 1;;
        if($qseq_stop > $L) { 
          $qseq_start -= $L;
          $qseq_start -= 1; # off-by-one issue with negative indexing
          $qseq_stop  -= $L;
        }
        if(! exists $coords_HAR->{$accn}) { 
          @{$coords_HAR->{$accn}} = ();
        }
        push(@{$coords_HAR->{$accn}}, $qseq_start . ":" . $qseq_stop);
        # printf("Found $qseq in $accn at position %d..%d\n", $qseq_start, $qseq_stop);
      }
      $qseq_posn = index($seq, $qseq, $qseq_posn);
    }
  }
  
  return;
}

# Subroutine: checkStrictBoundaryMatch
#
# Synopsis:   Check if a given start..stop boundary set matches the 
#             actual annotation in $act_AAR->[$cds_i][$exon_i]
#             (if that array element even exists).
#
# Args:       $act_start_AAR: ref to 2D array [0..i..$ncds-1][0..e..$nexon-1], start for cds $i+1 exon $e+1
#             $act_stop_AAR:  ref to 2D array [0..i..$ncds-1][0..e..$nexon-1], stop for cds $i+1 exon $e+1
#             $cds_i:         CDS index we want to check against
#             $exon_i:        exon index we want to check against
#             $pstart:        predicted start boundary
#             $pstop:         predicted stop boundary
# Returns:    Two values:
#             '1' if $pstart == $act_start_AAR->[$cds_i][$exon_i], else '0'
#             '1' if $pstop  == $act_stop_AAR->[$cds_i][$exon_i], else '0'
#
sub checkStrictBoundaryMatch {
  my $sub_name = "checkStrictBoundaryMatch";
  my $nargs_exp = 6;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($act_start_AAR, $act_stop_AAR, $cds_i, $exon_i, $pstart, $pstop) = @_;

  my $retval1 = 
      ((exists ($act_start_AAR->[$cds_i])) && 
       (exists ($act_start_AAR->[$cds_i][$exon_i])) && 
       ($pstart == $act_start_AAR->[$cds_i][$exon_i])) ? 
       1 : 0;

  my $retval2 = 
      ((exists ($act_stop_AAR->[$cds_i])) && 
       (exists ($act_stop_AAR->[$cds_i][$exon_i])) && 
       ($pstop == $act_stop_AAR->[$cds_i][$exon_i])) ? 
       1 : 0;

  return ($retval1, $retval2);
}

# Subroutine: checkNonStrictBoundaryMatch
#
# Synopsis:   Check if a given boundary matches any
#             annotation in the 2D array referred to
#             by $act_AAR.
#
# Args:       $act_start_AAR: ref to 2D array [0..i..$ncds-1][0..e..$nexon-1], start for cds $i+1 exon $e+1
#     :       $act_stop_AAR:  ref to 2D array [0..i..$ncds-1][0..e..$nexon-1], stop for cds $i+1 exon $e+1
#             $pstart:        predicted start position
#             $pstop:         predicted stop position
# Returns:    Two values:
#             '1' if $pstart == $act_start_AAR->[$i][$e], else '0'
#             '1' if $pstop  == $act_stop_AAR->[$i][$e], else '0'
#             For any possible $i and $e values, as long as they are the same for start and stop
#             If both ('1', '0') and ('0', '1') are possible sets of return values, 
#             ('1', '0') is returned.
#
sub checkNonStrictBoundaryMatch {
  my $sub_name = "checkNonStrictBoundaryMatch";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($act_start_AAR, $act_stop_AAR, $pstart, $pstop) = @_;

  my $found_start_match = 0;
  my $found_stop_match = 0;
  my $found_both_match = 0;
  my $start_match = 0;
  my $stop_match = 0;
  my $ncds = scalar(@{$act_start_AAR});
  for(my $i = 0; $i < $ncds; $i++) { 
    my $nexons = scalar(@{$act_start_AAR->[$i]});
    if(! exists $act_stop_AAR->[$i]) { die "ERROR in checkNonStrictBoundaryMatch() $i exists in first dimension of start coords, but not stop coords"; }
    for(my $e = 0; $e < $nexons; $e++) { 
      if(! exists $act_stop_AAR->[$i][$e]) { die "ERROR in checkNonStrictBoundaryMatch() $i $e exists in start coords, but not stop coords"; }
      $start_match = ($pstart == $act_start_AAR->[$i][$e]) ? 1 : 0;
      $stop_match  = ($pstop  == $act_stop_AAR->[$i][$e])  ? 1 : 0;
      if($start_match && $stop_match) { $found_both_match  = 1; }
      elsif($start_match)             { $found_start_match = 1; }
      elsif($stop_match)              { $found_stop_match = 1; }
    }
  }

  if   ($found_both_match)  { return (1, 1); }
  elsif($found_start_match) { return (1, 0); }
  elsif($found_stop_match)  { return (0, 1); }
  else                      { return (0, 0); }
}

# Subroutine: validateOriginSeq
#
# Synopsis:   Validate an origin sequence passed in
#             as <s> with --oseq <s>. It should have 
#             a single '|' in it, which occurs 
#             just before what should be the first nt
#             of the genome. Return the origin offset:
#             the number of nts before the "|".
#
#             For example: "TAATATT|AC"
#             indicates that the final 7 nts of each
#             genome should be "TAATAAT" and the first
#             two should be "AC". In this case the origin
#             offset is 7.
#
# Args:       $origin_seq: the origin sequence
#
# Returns:    Origin offset, as explained in synopsis, above.
#
sub validateOriginSeq {
  my $sub_name = "validateOriginSeq";
  my $nargs_exp = 1;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($origin_seq) = @_;

  my $origin_offset = index($origin_seq, "|");
  if($origin_offset == -1) { 
    die "ERROR with --oseq <s>, <s> must contain a single | character immediately before the nucleotide that should be the first nt of the genome";
  }
  my $second_offset = index($origin_seq, "|", $origin_offset+1);
  if($second_offset != -1) { 

    die "ERROR with --oseq <s>, <s> must contain a single | character, $origin_seq has more than one";
  }

  #printf("in $sub_name, $origin_seq returning $origin_offset\n");

  return $origin_offset;
}

# Subroutine: fetchCodon()
#
# Synopsis:   Fetch a codon given it's first position
#             and the strand and a Bio::Easel::SqFile object
#             that is the open sequence file with the desired
#             sequence.
#
# Args:       $sqfile:  Bio::Easel::SqFile object, open sequence
#                       file containing $seqname;
#             $seqname: name of sequence to fetch part of
#             $start:   start position of the codon
#             $strand:  strand we want ("+" or "-")
#
# Returns:    The codon as a string
#
sub fetchCodon {
  my $sub_name = "fetchCodon";
  my $nargs_exp = 4;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($sqfile, $seqname, $start, $strand) = @_;

  my $codon_start = $start;
  my $codon_stop  = ($strand eq "-") ? $start - 2 : $start + 2; 

  my $newname = $seqname . "/" . $codon_start . "-" . $codon_stop;

  my @fetch_AA = ();
  push(@fetch_AA, [$newname, $codon_start, $codon_stop, $seqname]);

  my $faseq = $sqfile->fetch_subseqs(\@fetch_AA, -1);

  my ($header, $seq) = split("\n", $faseq);

  # printf("$faseq");
  
  return $seq;
}

# Subroutine: monocharacterString()
#
# Synopsis:   Return a string of length $len of repeated
#             instances of the character $char.
#
# Args:       $len:   desired length of the string to return
#             $char:  desired character
#
# Returns:    A string of $char repeated $len times.
#
sub monocharacterString {
  my $sub_name = "monocharacterString";
  my $nargs_exp = 2;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($len, $char) = @_;

  my $ret_str = "";
  for(my $i = 0; $i < $len; $i++) { 
    $ret_str .= $char;
  }

  return $ret_str;
}

# Subroutine: alignHits()
#
# Synopsis:   Given 2D hashes that describe all hits, fetch
#             the hits for each CDS/exon to a file and then 
#             align all those sequences to the appropriate 
#             model to create a multiple alignment.
#
# Args:       $align:        path to hmmalign or cmalign executable
#             $fetch:        path to hmmfetch or cmfetch executable
#             $model_db:     model database file to fetch the models from
#             $sqfile:       Bio::Easel::SqFile object, open sequence
#                            file containing $seqname;
#             $mdl_order_AR: ref to array of model names in order
#             $seq_order_AR: ref to array of sequence names in order
#             $seqlen_HR:    ref to hash of total lengths
#             $start_HHR:    ref to 2D hash of start values, pre-filled
#             $stop_HHR:     ref to 2D hash of stop values, pre-filled
#             $strand_HHR:   ref to 2D hash of strand values, pre-filled
#             $fid2ref_HHR:  ref to 2D hash of fractional identity values 
#                            of aligned sequences to the reference, FILLED HERE
#             $out_aln_root: root name for output files
# 
# Returns:    void
#
sub alignHits {
  my $sub_name = "hmmalignHits";
  my $nargs_exp = 12;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($align, $fetch, $model_db, $sqfile, $mdl_order_AR, $seq_order_AR, $seqlen_HR, $start_HHR, $stop_HHR, $strand_HHR, $fid2ref_HHR, $out_aln_root) = @_;

  foreach my $mdl (@{$mdl_order_AR}) { 
    my @fetch_AA = ();
    my $nseq = 0;
    for(my $seq_i = 0; $seq_i < scalar(@{$seq_order_AR}); $seq_i++) { 
      my $seq = $seq_order_AR->[$seq_i];
      if($seq_i == 0 && (! exists $start_HHR->{$mdl}{$seq})) {
        die "ERROR in $sub_name(), no hit from model $mdl to the reference sequence $seq"; 
      }
      if(exists $start_HHR->{$mdl}{$seq}) { 
        my $accn = $seq;
        $accn =~ s/\:.+$//;
        my $newname .= $accn . "/" . $start_HHR->{$mdl}{$seq} . "-" . $stop_HHR->{$mdl}{$seq};
        my $start = $start_HHR->{$mdl}{$seq};
        my $stop  = $stop_HHR->{$mdl}{$seq};
        if($start < 0 || $stop < 0) { 
          $start += $seqlen_HR->{$accn};
          $stop  += $seqlen_HR->{$accn};
        }
        push(@fetch_AA, [$newname, $start, $stop, $seq]);
        $nseq++;
      }
    }
    if($nseq > 0) { 
      my $cur_fafile = $out_aln_root . "." . $mdl . ".fa";
      $sqfile->fetch_subseqs(\@fetch_AA, undef, $cur_fafile);
      # printf("Saved $nseq sequences to $cur_fafile.\n");
      
      # create the alignment
      my $cur_stkfile = $out_aln_root . "." . $mdl . ".stk";
      my $cmd = "$fetch $model_db $mdl | $align - $cur_fafile > $cur_stkfile";
      #print $cmd . "\n";
      runCommand($cmd, 0);
      # printf("Saved $nseq aligned sequences to $cur_stkfile.\n");

      # store the fractional identities between each sequence and the reference
      # first we need to read in the MSA we just created 
      my $msa = Bio::Easel::MSA->new({
        fileLocation => $cur_stkfile,
                                     });  

      my $i = 0; # this will remain '0', which is the reference sequence
      my $j = 0; # we'll increment this from 0..$nseq-1
      foreach my $seq (@{$seq_order_AR}) { 
        if(exists $start_HHR->{$mdl}{$seq}) { 
          $fid2ref_HHR->{$mdl}{$seq} = $msa->pairwise_identity($i, $j);
          # printf("storing percent id of $fid2ref_HHR->{$mdl}{$seq} for $mdl $seq\n"); 
          $j++;
        }
      }
    }
  }

  return;
}

# Subroutine: checkForOverlaps()
#
# Synopsis:   Given refs to three arrays that describe 
#             a list of hits, check if any of them overlap.
#
# Args:       $name_AR:         ref to array of short names for each annotation
#             $start_AR:        ref to array of start positions
#             $stop_AR:         ref to array of stop positions
#             $strand_AR:       ref to array of strands
#             $expected_ol_AAR: ref to 2D array of expected overlaps $expected_ol_AAR->[$i][$j] is '1' if 
#                               those two exons are expected to overlap, PRE-FILLED, 
#                               can be undefined
#             $return_ol_AAR:   ref to 2D array of observed overlaps $observed_ol_AAR->[$i][$j] is '1' if 
#                               those two exons are observed to overlap here, FILLED HERE,
#                               can be undefined
# 
# Returns:    Two values:
#             $pass_fail_char: "P" if overlaps match those in $expected_ol_AAR, else "F"
#                              if $expected_ol_AAR is undef, always return "P"
#             $overlap_notes:  string describing the overlaps, empty string ("") if no overlaps.
#
sub checkForOverlaps {
  my $sub_name = "checkForOverlaps";
  my $nargs_exp = 6;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($name_AR, $start_AR, $stop_AR, $strand_AR, $expected_ol_AAR, $return_ol_AAR) = @_;

  my $ret_str = "";

  my @observed_ol_AA = (); # [$i][$j] is '1' if we observe an overlap between $i and $j (or $j and $i), else 0

  my $nhits = scalar(@{$name_AR});

  # initialize
  for(my $i = 0; $i < $nhits; $i++) { 
    for(my $j = 0; $j < $nhits; $j++) { 
      $observed_ol_AA[$i][$j] = 0;
    }
  }

  my $noverlaps = 0;
  for(my $i = 0; $i < $nhits; $i++) { 
    my $start_i  = $start_AR->[$i];
    my $stop_i   = $stop_AR->[$i];
    if($start_i > $stop_i) { 
      my $tmp  = $start_i;
      $start_i = $stop_i;
      $stop_i  = $tmp;
    }
    for(my $j = $i+1; $j < $nhits; $j++) { 
      my $start_j  = $start_AR->[$j];
      my $stop_j   = $stop_AR->[$j];
      if($start_j > $stop_j) { 
        my $tmp  = $start_j;
        $start_j = $stop_j;
        $stop_j  = $tmp;
      }
      my $nres_overlap = get_nres_overlap($start_i, $stop_i, $start_j, $stop_j);
      if($nres_overlap > 0) { 
        $noverlaps++;
        $observed_ol_AA[$i][$j] = 1;
        $observed_ol_AA[$j][$i] = 1;
        # $ret_str .= sprintf("%s overlaps with %s (%s);", $name_AR->[$i], $name_AR->[$j], ($strand_AR->[$i] eq $strand_AR->[$j]) ? "same strand" : "opposite strands");
        if($ret_str ne "") { 
          $ret_str .= " ";
        }
        $ret_str .= sprintf("%s/%s", $name_AR->[$i], $name_AR->[$j]); 
      }
      else { # no overlap
        $observed_ol_AA[$i][$j] = 0;
        $observed_ol_AA[$j][$i] = 0;
      }
    }
  }

  # check @observed_ol_AA against @{$expected_ol_AAR} and/or
  # copy @observed_ol_AA to @{$return_ol_AAR}
  my $pass_fail_char = "P";
  for(my $i = 0; $i < $nhits; $i++) { 
    for(my $j = 0; $j < $nhits; $j++) { 
      if(defined $expected_ol_AAR) { 
        if($observed_ol_AA[$i][$j] ne $expected_ol_AAR->[$i][$j]) { 
          $pass_fail_char = "F";
        }
      }
      if(defined $return_ol_AAR) {
        $return_ol_AAR->[$i][$j] = $observed_ol_AA[$i][$j];
      }
    }
  }

  if($ret_str ne "") { 
    $ret_str = $pass_fail_char . " " . $noverlaps . " " . $ret_str;
  }

  return ($pass_fail_char, $ret_str);
}

# Subroutine: get_nres_overlap()
# Args:       $start1: start position of hit 1 (must be <= $end1)
#             $end1:   end   position of hit 1 (must be >= $end1)
#             $start2: start position of hit 2 (must be <= $end2)
#             $end2:   end   position of hit 2 (must be >= $end2)
#
# Returns:    Number of residues of overlap between hit1 and hit2,
#             0 if none
# Dies:       if $end1 < $start1 or $end2 < $start2.

sub get_nres_overlap {
  if(scalar(@_) != 4) { die "ERROR get_nres_overlap() entered with wrong number of input args"; }

  my ($start1, $end1, $start2, $end2) = @_; 

  #printf("in get_nres_overlap $start1..$end1 $start2..$end2\n");

  if($start1 > $end1) { die "ERROR start1 > end1 ($start1 > $end1) in get_nres_overlap()"; }
  if($start2 > $end2) { die "ERROR start2 > end2 ($start2 > $end2) in get_nres_overlap()"; }

  # Given: $start1 <= $end1 and $start2 <= $end2.
  
  # Swap if nec so that $start1 <= $start2.
  if($start1 > $start2) { 
    my $tmp;
    $tmp   = $start1; $start1 = $start2; $start2 = $tmp;
    $tmp   =   $end1;   $end1 =   $end2;   $end2 = $tmp;
  }
  
  # 3 possible cases:
  # Case 1. $start1 <=   $end1 <  $start2 <=   $end2  Overlap is 0
  # Case 2. $start1 <= $start2 <=   $end1 <    $end2  
  # Case 3. $start1 <= $start2 <=   $end2 <=   $end1
  if($end1 < $start2) { return 0; }                      # case 1
  if($end1 <   $end2) { return ($end1 - $start2 + 1); }  # case 2
  if($end2 <=  $end1) { return ($end2 - $start2 + 1); }  # case 3
  die "Unforeseen case in get_nres_overlap $start1..$end1 and $start2..$end2";

  return; # NOT REACHED
}


# Subroutine: printColumnHeaderExplanations()
# Args:       $do_oseq: '1' if -oseq was enabled
#
# Returns:    void

sub printColumnHeaderExplanations {
  my $sub_name = "printColumnHeaderExplanations";
  my $nargs_exp = 8;
  if(scalar(@_) != $nargs_exp) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($do_oseq, $do_nomdlb, $do_noexist, $do_nobrack, $do_nostop, $do_nofid, $do_noss3, $do_noolap) = @_; 
  
  print("#\n");
  print("# Explanations of column headings (in left to right order):\n");

  my $width = 35;

  printf("# %-*s %s\n", $width, "\"accession\":", "GenBank accession for genomic sequence");
  printf("# %-*s %s\n", $width, "\"totlen\":",    "total length (nt) for accession");

  if($do_oseq) {
    printf("#\n");
    printf("# %-*s %s\n", $width, "\"origin sequence: #\":",      "number of occurences of origin sequence (input with -oseq) in genome");
    printf("# %-*s %s\n", $width, "\"origin sequence: start\":",  "start position of lone occurence of origin sequence (if only 1 exists)");
    printf("# %-*s %s\n", $width, "\"origin sequence: stop\":",   "stop  position of lone occurence of origin sequence (if only 1 exists)");
    printf("# %-*s %s\n", $width, "\"origin sequence: offst\":",  "predicted offset of genome, number of nucleotides to shift start (>0: clockwise; <0: counterclockwise)");
    printf("# %-*s %s\n", $width, "\"origin sequence: PF\":",     "'P' (for PASS) if there is exactly 1 occurence of the offset, else 'F' for FAIL");
  }

  printf("#\n");
  printf("# %-*s %s\n", $width, "\"CDS #<i>: start<j>\":", "start position of exon #<j> of CDS #<i>");
  printf("# %-*s %s\n", $width, "\"CDS #<i>: stop<j>\":",  "stop  position of exon #<j> of CDS #<i>");

  if(! $do_nofid) { 
    printf("# %-*s %s\n", $width, "\"CDS #<i>: fid<j>\":",  "fractional identity between exon #<j> of CDS #<i> and reference genome");
  }

  if(! $do_nomdlb) { 
    printf("# %-*s %s\n", $width, "\"CDS #<i>: md<j>\":",  "annotation indicating if alignment to reference extends to 5' and 3' end of reference exon.");
    printf("# %-*s %s\n", $width, "",                      "first character pertains to 5' end and second character pertains to 3' end.");
    printf("# %-*s %s\n", $width, "",                      "possible values for each of the two characters:");
    printf("# %-*s %s\n", $width, "",                      "  \".\":   alignment extends to boundary of reference");
    printf("# %-*s %s\n", $width, "",                      "  \"<d>\": alignment truncates <d> nucleotides short of boundary of reference (1 <= <d> <= 9)");
    printf("# %-*s %s\n", $width, "",                      "  \"+\":   alignment truncates >= 10 nucleotides short of boundary of reference");
  }

  printf("# %-*s %s\n", $width, "\"CDS #<i>: length\":",   "length of CDS #<i> (all exons summed)");

  if(! $do_noss3) { 
    print("#\n");
    printf("# %-*s %s\n", $width, "\"CDS #<i>: SS3\":",   "annotation indicating if predicted CDS has a valid start codon, stop codon and is a multiple of 3");
    printf("# %-*s %s\n", $width, "",                      "first  character: '.' if predicted CDS has a valid start codon, else '!'");
    printf("# %-*s %s\n", $width, "",                      "second character: '.' if predicted CDS has a valid stop  codon, else '!'");
    printf("# %-*s %s\n", $width, "",                      "third  character: '.' if predicted CDS has a length which is a multiple of three, else '!'");
  }

  if(! $do_nostop) { 
    printf("# %-*s %s\n", $width, "\"CDS #<i>: stp\":",   "the predicted stop codon for this CDS");
  }

  printf("# %-*s %s\n", $width, "\"CDS #<i>: PF\":",      "annotation indicating if this exon PASSED ('P') or FAILED ('F')");
  printf("# %-*s %s\n", $width, "",                       "an exon PASSES ('P') if and only if it has a valid start codon, stop codon");
  printf("# %-*s %s\n", $width, "",                       "  is a length that is a multiple of 3, and has an alignment to the reference");
  printf("# %-*s %s\n", $width, "",                       "  that extends to the 5' and 3' boundary of the reference annotation.");
  printf("# %-*s %s\n", $width, "",                       "  If >= 1 of these conditions is not met then the exon FAILS ('F').");

  print("#\n");
  printf("# %-*s %s\n", $width, "\"totlen\":",            "total length (nt) for accession (repeated for convenience)"); 
  
  if(! $do_noexist) { 
    printf("#\n");
    printf("# %-*s %s\n", $width, "\"existing annotation: cds\"",   "number of CDS in the existing NCBI annotation for this accession");
    printf("# %-*s %s\n", $width, "\"existing annotation: exons\"", "total number of exons in the existing NCBI annotation for this accession");
    printf("# %-*s %s\n", $width, "\"existing annotation: match\"", "number of exons in existing NCBI annotation for which existing and predicted annotation agree exactly");
  }

  if(! $do_noolap) { 
    printf("#\n");
    printf("# %-*s %s\n", $width, "\"overlaps\?\"",   "text describing which (if any) of the predicted exons overlap with each other");
    printf("# %-*s %s\n", $width, "",                 "first character:   'P' for PASS if predicted annotation for this accession has same overlaps as the reference");
    printf("# %-*s %s\n", $width, "",                 "                   'F' for FAIL if it does not");
    printf("# %-*s %s\n", $width, "",                 "second character:  number of overlaps between any two exons");
    printf("# %-*s %s\n", $width, "",                 "remainder of line: text explaining which exons overlap");
    printf("# %-*s %s\n", $width, "",                 "  e.g.: \"3.2/4.1\" indicates exon #2 of CDS #3 overlaps with exon #1 of CDS #4 on either strand");
  }  

  print("#\n");
  printf("# %-*s %s\n", $width, "\"result\":",            "\"PASS\" or \"FAIL\". \"PASS\" if and only if all tests for this accession PASSED ('P')");
  printf("# %-*s %s\n", $width, "",                       "as indicated in the \"PF\" columns. Followed by the individual P/F results in order.");
  if($do_noolap) { 
    printf("# %-*s %s\n", $width, "",                       "Final P/F in the results pertains to the overlap check: 'P' if this accession has the same");
    printf("# %-*s %s\n", $width, "",                       "set of overlaps as the reference accession, and 'F' if not.");
  }    

  return; 
}
