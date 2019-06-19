#!/bin/bash -e

## 
## This script extracts high-fidelity audio (in OGG format) from the
## librispeech mp3 archive using the splits from of the prepared sets (e.g.
## clean-360). The idea here is to overcome the 16kHz limitation of the prepared
## sets but keep their splitting and balancing.
## 
## usage: create_hifi_version.sh [OPTIONS]
## 
## options:
##      -i --coarse-hifi <path>     location of the librispeech's unpacked mp3 archive
##      -s --splitted-lofi <path>   location of the unpacked prepared lo-fi subset to use as a template
##      -o --output-dir <path>      target folder to put hi-fi files to
##      -t --samplerate <path>      target samplerate of the hi-fi files
##      -h                          print help and exit

OPTIONS=i:s:o:t:h
LONGOPTS=coarse-hifi:,splitted-lofi:,output-dir:,samplerate:,help
HELP=$(sed -ne 's/^## \(.*\)/\1/p' $0)

# -use ! and PIPESTATUS to get exit code with errexit set
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi

# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

samplerate=22050
# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -i|--coarse-hifi)
            hifi="$2"
            shift 2
            ;;
        -s|--splitted-lofi)
            lofi="$2"
            shift 2
            ;;
        -o|--output-dir)
            odir="$2"
            shift 2
            ;;
        -t|--samplerate)
            samplerate="$2"
            shift 2
            ;;
        -h|--help)
            echo "$HELP"
            exit 1
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Something is wrong with getopt :("
            echo "$1"
            exit 3
            ;;
    esac
done

if [ -z "$hifi" ]; then
    echo "-i was not provided!"
    echo "$HELP"
    exit 1
fi
if [ -z "$lofi" ]; then
    echo "-s was not provided!"
    echo "$HELP"
    exit 1
fi
if [ -z "$odir" ]; then
    echo "-o was not provided!"
    echo "$HELP"
    exit 1
fi

# handle non-option arguments
if [[ $# -ne 0 ]]; then
    echo "$0: unexpected arguments!"
    echo "$HELP"
    exit 4
fi

###############################################################################
# ACTUAL SCRIPT
###############################################################################

for spkpath in $(find $lofi -maxdepth 1 -mindepth 1 -type d)
#for spkpath in ./LibriSpeech/train-clean-460/100
do
    spk=${spkpath##*/}
    lofi_utters=$(find $spkpath -name *.flac -printf "%f\n" | sed 's/.flac//')
    uttermapfile=$hifi/$spk/utterance_map.txt
    lofi_hifi_utters=$(join -j 1 -o 1.1,1.2\
                       <(sed '1,2d' $uttermapfile | sort -n)\
                       <(echo "$lofi_utters" | sort -n))
    
    cuts=$(find $hifi/$spk ! -name "*sent*" -a\
                           ! -name "*intro*" -a\
                           -name "*.seg.txt" | xargs cat | sort -n -k1)

    # this will have columns: lofi_utter hifi_utter t_start t_stop
    utters_cuts=$(join -1 2 -2 1 -o 1.1,2.2,2.3\
                  <(echo "$lofi_hifi_utters")\
                  <(echo "$cuts"))

    while IFS=' ' read -r lofi_utter tstart tstop
    do 
        if [[ $lofi_utter =~ ^[0-9]+-([0-9]+)[-_].* ]]; then
            book=${BASH_REMATCH[1]}
        else
            echo "Something went wrong with matching regexp"
            exit 1
        fi

        hifi_file=${hifi}/${spk}/${book}/${book}.mp3
        target_file=${odir}/${spk}/${book}/${lofi_utter}.ogg
        target_file_tmp=${odir}/${spk}/${book}/${lofi_utter}_tmp.ogg

        mkdir -p $(dirname $target_file)
        sox $hifi_file $target_file_tmp trim =$tstart =$tstop
        sox $target_file_tmp -C 10 -r $samplerate -c 1 --norm=-3 $target_file
        rm $target_file_tmp

        echo $target_file
        trap exit_ int
    done < <(echo "$utters_cuts")
done
