#!/usr/bin/perl
# LMU Munich. AG Enard
# A script to filter reads based on Barcode base quality.

if(@ARGV != 6)
{
print
"\n#####################################################################################
Usage: perl $0 <yaml> <samtools-executable> <rscript-executable> <pigz-executable> <zUMIs-dir> <tmpPrefix>\n
Please drop your suggestions and clarifications to <sparekh\@age.mpg.de>\n
######################################################################################\n\n";
exit;
}
BEGIN{
$yml=$ARGV[0];
$samtoolsexc=$ARGV[1];
$rscriptexc=$ARGV[2];
$pigz=$ARGV[3];
$zumisdir=$ARGV[4];
$tmpPrefix=$ARGV[5];
}
use lib "$zumisdir";
use distilReads;

open(YL,"Rscript $zumisdir/readYaml4fqfilter.R $yml |");
@arg=<YL>;
close YL;
%argHash;
@params=("filenames", "seqtype", "outdir", "StudyName", "num_threads", "BCfilter", "UMIfilter", "find_pattern");


for($i=0;$i<=$#params;$i++){
  $argHash{$params[$i]}=$arg[$i];
}

# parse the fastqfiles and make a hash with file handles as key and filename.pattern as value
$f = distilReads::argClean($argHash{"filenames"});
$st = distilReads::argClean($argHash{"seqtype"});
$outdir = distilReads::argClean($argHash{"outdir"});
$StudyName = distilReads::argClean($argHash{"StudyName"});
$num_threads = distilReads::argClean($argHash{"num_threads"});
$BCfilter = distilReads::argClean($argHash{"BCfilter"});
$UMIfilter = distilReads::argClean($argHash{"UMIfilter"});
$pattern = distilReads::argClean($argHash{"find_pattern"});
#/data/share/htp/Project_mcSCRB-seqPaper/PEG_May2017/demult_HEK_r1.fq.gz; /data/share/htp/Project_mcSCRB-seqPaper/PEG_May2017/demult_HEK_r2.fq.gz;ACTGCTGTA
chomp($f);
chomp($st);
chomp($outdir);
chomp($StudyName);
chomp($num_threads);
chomp($BCfilter);
chomp($UMIfilter);
chomp($pattern);

$outbcstats = "$outdir/zUMIs_output/.tmpMerge/$StudyName.$tmpPrefix.BCstats.txt";
$outbam = "$outdir/zUMIs_output/.tmpMerge/$StudyName.$tmpPrefix.filtered.tagged.bam";

# Make and open all the file handles
%file_handles = distilReads::makeFileHandles($f,$st,$pattern);

# First file handle to start the while loop for the first file
@keys = sort(keys %file_handles);
$fh1 = $keys[0];
@fp1 = split(":",$file_handles{$fh1});

for($i=0;$i<=$#keys;$i++){
  $fh = $keys[$i];
  @fp = split(":",$file_handles{$fh});

  if ($fp[0] =~ /\.gz$/) {
		$oriF = $fp[0];
		$oriBase = `basename $oriF .gz`;
    chomp($oriBase);

		#change the file name to temporary prefix for its chunk
		$chunk = "$outdir/zUMIs_output/.tmpMerge/$oriBase$tmpPrefix.gz";
    open $fh, '-|', $pigz, '-dc', $chunk || die "Couldn't open file ".$chunk.". Check permissions!\n Check if it is differently zipped then .gz\n\n";
  }else {

		$oriF = $fp[0];
		$oriBase = `basename $oriF'`;
		#change the file name to temporary prefix for its chunk
		$chunk = "$outdir/zUMIs_output/.tmpMerge/$oriBase$tmpPrefix.gz";

    open $fh, "<", $chunk || die "Couldn't open file ".$chunk.". Check permissions!\n Check if it is differently zipped then .gz\n\n";
  }
}

$total = 0;
$filtered = 0;
%bclist;

open(BCBAM,"| samtools view -Sb - > $outbam");

# reading the first file while others are processed in parallel within
while(<$fh1>){
  $total++;
  $rid=$_;
	$rseq=<$fh1>;
	$qid=<$fh1>;
	$qseq=<$fh1>;
	$p1 = $fp1[1];
  $p2 = $fp1[2];

#This block checks if the read should have certian pattern
  if($p2 =~ /^character/){
    $mcrseq = $rseq;
    $checkpattern = $rseq;
  }
  else{
    $mcrseq = $rseq;
    $checkpattern = $p2;
  }

  if($count==0){
    $count=1;
    $phredoffset = distilReads::checkPhred($qseq);
  }
  ($bcseq, $bcqseq, $ubseq, $ubqseq, $cseqr1, $cqseqr1, $cseqr2, $cqseqr2, $cdc, $lay) = ("","","","","","","","",0,"SE");
  ($bcseq, $bcqseq, $ubseq, $ubqseq, $cseqr1, $cqseqr1, $cseqr2, $cqseqr2, $cdc, $lay) = distilReads::makeSeqs($rseq,$qseq,$p1,$cdc);

	for($i=1;$i<=$#keys;$i++){
    $fh = $keys[$i];
    @fp = split(":",$file_handles{$fh});

		$rid1=<$fh>;
		$rseq1=<$fh>;
		$qid1=<$fh>;
		$qseq1=<$fh>;
    $p = $fp[1];
    $pf = $fp[2];

    #This block checks if the read should have certian pattern
    if($pf =~ /^character/){
      $mcrseq = $rseq1;
      $checkpattern = $rseq1;
    }
    else{
      $mcrseq = $rseq1;
      $checkpattern = $pf;
    }

    @c = split(/\/|\s/,$rid);
    @b = split(/\/|\s/,$rid1);
    if($c[0] ne $b[0]){
      print "ERROR! Fastq files are not in the same order.\n Make sure to provide reads in the same order.\n\n";
      last;
    }

    # get the BC, UMI and cDNA sequences from all the given fastq files and concatenate according to given ranges
    ($bcseq1, $bcqseq1, $ubseq1, $ubqseq1, $cseq1, $cqseq1, $cseq2, $cqseq2, $cdc, $lay) = distilReads::makeSeqs($rseq1,$qseq1,$p,$cdc);

    # concatenate according to given ranges with other files
    ($bcseq, $bcqseq, $ubseq, $ubqseq, $cseqr1, $cqseqr1, $cseqr2, $cqseqr2) = ($bcseq.$bcseq1, $bcqseq.$bcqseq1, $ubseq.$ubseq1, $ubqseq.$ubqseq1, $cseqr1.$cseq1, $cqseqr1.$cqseq1, $cseqr2.$cseq2, $cqseqr2.$cqseq2);
	}

    # Check the quality filter thresholds given
    @bcthres = split(" ",$BCfilter);
    @umithres = split(" ",$UMIfilter);

    # map to the correct phredoffset and get the number of bases under given quality threshold
    @bquals = map {$_ - $phredoffset} unpack "C*", $bcqseq;
    @mquals = map {$_ - $phredoffset} unpack "C*", $ubqseq;
    $btmp = grep {$_ < $bcthres[1]} @bquals;
    $mtmp = grep {$_ < $umithres[1]} @mquals;


    # print out only if above the quality threshold
    if(($btmp < $bcthres[0]) && ($mtmp < $umithres[0]) && ($mcrseq =~ m/^$checkpattern/)){
    #if(($btmp < $bcthres[0]) && ($mtmp < $umithres[0])){

      chomp($rid);

      if($rid =~ m/^\@.*\s/){
        $rid =~ m/^\@(.*)\s/;
        $ridtmp = $1;
      }
      else{
        $rid =~ m/^\@(.*)/;
        $ridtmp = $1;
      }

      $filtered++;
      $bclist{$bcseq}++;
      #print $lay,"\n";
      if($lay eq "SE"){
        print BCBAM $ridtmp,"\t4\t*\t0\t0\t*\t*\t0\t0\t",$cseqr1,"\t",$cqseqr1,"\tBC:Z:",$bcseq,"\tUB:Z:",$ubseq,"\n";
      }else{
        print BCBAM $ridtmp,"\t77\t*\t0\t0\t*\t*\t0\t0\t",$cseqr1,"\t",$cqseqr1,"\tBC:Z:",$bcseq,"\tUB:Z:",$ubseq,"\n";
        print BCBAM $ridtmp,"\t141\t*\t0\t0\t*\t*\t0\t0\t",$cseqr2,"\t",$cqseqr2,"\tBC:Z:",$bcseq,"\tUB:Z:",$ubseq,"\n";
      }
    }
}
close BCBAM;
for($i=0;$i<=$#keys;$i++){  close $keys[$i]; }

open BCOUT, '>', $outbcstats || die "Couldn't open file ".$outbcstats.". Check permissions!\n";
foreach $bc (keys %bclist){
  print BCOUT $bc,"\t",$bclist{$bc},"\n";
}
close BCOUT;
