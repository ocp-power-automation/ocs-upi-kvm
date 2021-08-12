#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021-
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

#VERSION="20210811_1628"

################################################################################
# This is a simple script that collects logs and html files from the server(s) 
# indicated on the arguments, then it pulls it into the current dir.
################################################################################
ARGUMENTS=""
PREPATH="logs-ocs-ci" #Holds the initial part of the path to follow.
COMMON=0    #When the value is "1" ignore the use of month_day directories.
DAY=""      # contains the day part of the date used to gather files.
FINDARG=""  # used to indicate the argument to find.
FOUNDARG="" # auxilary indicates if an argument has been found.
GSADIR="/tucgsa-h2/08/cpratt/OCSReports/OCS48/" #for now let's use this dir.
GETDIR=""   # used through the script as a generic get directory/path name.
HTMLF=""    # used only to identify HTML files.
LOGPATH=""  # Path to the logs from where we will select the logs to transfer.
RHOST=""    # has the IP or name of the remote host.
MDY=""      # holds a date on the form month/Day/year.
MDYF=""     # holds a date to be used on the name of a dir.
MONTH=""    # holds the name of the month to be used for the selection of files.
MONTHN=""   # Holds the name of a month abreviated to three letters.
MONTHS=(Pad Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec) #month names table.
NEXTVAR=""  # used to find the next value after identifying the argument.
TARGET="$(pwd)" #Holds the target directory for the files to be stored.
TRSFRGSA="1" # if this variable is 0 then do not transfer anything to GSA
USER=""     # the user name.
VPATH="4.8" #Holds the version path it defaults to 4.8 but it can use 4.6 to 4.9.
VRBS=0 #for debug

################################################################################
# This is the find arg function.
# if  the argument to be found, contained in the FIND variable is found, then it
# is passed through FOUNDARG
################################################################################
function findarg(){
    if [[ VRBS -eq 1 ]]; then
	echo -e "in findarg"
	echo -e "Argument(s) to find $1"
    fi
    FOUNDARG=1
    case $1 in
	"-c")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    COMMON=1
	    ;;
	"-d")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    NEXTVAR="mnthdy"
	    ;;	
	"-h")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    help
	    exit 0
	    ;;
	"-p")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    NEXTVAR="gtdr"
	    ;;
	"-s")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    NEXTVAR="hst"
	    ;;
	"-t")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    NEXTVAR="trgt"
	    ;;
	"-u")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    NEXTVAR="rd"
	    ;;
	"-v")
	    if [[ VRBS -eq 1 ]]; then
		echo -e "found $1"
	    fi
	    NEXTVAR="vrsn"
	    ;;
	*)
	    if [[ VRBS -eq 1 ]]; then
		echo -e "Not found $1"
	    fi
	    NEXTVAR=""
	    FOUNDARG=0
	    ;;
    esac
}


################################################################################
# This is the help function. is self explanatory.
################################################################################
function help(){
    clear
    echo -e "This script helps to copy files from a remote  server/host to"
    echo -e "your local machine. The files copied are log-files (.log) and"
    echo -e "report files (.html)"
    echo -e "The GSAID and SSHPASS environment  variables need to be set to"
    echo -e "the authorized user and password. If they are not  present the"
    echo -e "files will not be transferred to GSA using sftp.\n"
    echo -e "you  can  change  the  behavior  of  the script using the next"
    echo -e "arguments:"
    echo -e " -c Uses the same directory for all found files. The files are"
    echo -e "    not distributed in subdirectories  representing the  month"
    echo -e "    and day they were created."
    echo -e " -d The argument following must be a date on the form m/d/yyyy"
    echo -e "    or mm/dd/yyyy. This is the  date of the  files to extract."
    echo -e "    Sometimes  files  from the previous day may appear in this"
    echo -e "    directory."
    echo -e " -h Displays this help."
    echo -e " -p The following  argument is the directory in the remote host"
    echo -e "    that  contains  the  subdirectory with the running version."
    echo -e " -s Following  this modifier must be the name or the IP address"
    echo -e "    of the  remote  host/server  from  where  the  data will be"
    echo -e "    extracted."
    echo -e " -t The argument following is the target directory in the"
    echo -e "    local machine.  If none is given, then the current directory"
    echo -e "    is used."
    echo -e " -u The argument following this modifier must be the username to"
    echo -e "    be used.  It is assumed that this user has a key that allows"
    echo -e "    a server/host  passwordless  connection.  If this is not the"
    echo -e "    case, a password will be prompted multiple times."
    echo -e " -v The  following  argument  must  contain  the  OCS version of"
    echo -e "    interest. Not providing it will default to version 4.8."
    echo -e "==============================================================="
}

function verifytarget(){
    SPCHAR="_"
    if [ $COMMON == 1 ]; then
	if [ $VRBS -eq 1 ]; then
	    echo -e "verifytarget: TARGET=$TARGET"
	fi
    else
	case "$DAY" in
	    " 1" | " 2" | " 3" | " 4" | " 5" | " 6" | " 7" | " 8" | " 9")
		DAY=${DAY:1}
		;;
	    *)
		;;
	esac
	if [ $VRBS -eq 1 ]; then
	    echo -e "verifytarget: TARGET=$TARGET"
	    echo -e "verifytarget: dir for date = $MONTHN$SPCHAR$DAY"		
	fi
	TARGET="$TARGET/$MONTHN$SPCHAR$DAY"
    fi

    # Verify the existence of the target directory, if it doesn't exist,
    # Create de directory where is supposed to be.
    if [ ! -d $TARGET ]; then
	mkdir -p $TARGET
    fi
    if [ $VRBS -eq 1 ]; then
	echo -e "\nverifytarget: TARGET verified is shown below:"
	echo -e "verifytarget: path => $TARGET"
    fi
    return 0;
}

################################################################################
# Above this line I have the functions and all the stuff needed for the script
# to run. I do this because if the script grows it can be hard to find where
# things start.
# Below this comment is the entry and main code.
################################################################################

################################################################################
#                          MAIN
################################################################################


###
# check to see if we have arguments.
###

if [ $# -eq 0 ]; then
    help
    exit 0
fi

###
# We got arguments start procesing them.
###
while (("$#")); do
    if [ $VRBS -eq 1 ]; then
	echo -e "$1"
	echo -e "$#"
    fi
    findarg $1
    #After finding the argument needed, we look, if applicable for its value
    case $NEXTVAR in
	"gtdr")
	    shift
	    PREPATH="$1/$PREPATH"
	    LOGPATH="$1/logs-cron"
	    if [ $VRBS -eq 1 ]; then
		echo -e "main: PREPATH=$PREPATH."
		echo -e "main: LOGPATH=$LOGPATH."		
	    fi
	    ;;
	"mnthdy")
	    shift
	    MDY=$1
	    MONTH=$(echo $1 | awk 'BEGIN { FS = "/" } ; { print $1 }')
	    DAY=$(echo $1 | awk 'BEGIN { FS = "/" } ; { print $2 }')
	    if [ "$DAY" -lt "10" ]; then
	       DAY=" "$DAY
	    fi
	    MONTHN=${MONTHS[$MONTH]}
	    if [ $VRBS -eq 1 ]; then
		echo -e "main: MONTH= $MONTH ($MONTHN)"
		echo -e "main: DAY= $DAY"		
	    fi
	    ;;
	"rd")
	    shift
	    USER="$1"
	    if [ $VRBS -eq 1 ]; then
		echo -e "main: USER=$USER."
	    fi
	    ;;
	"trgt")
	    shift
	    TARGET=$1
	    if [ $VRBS -eq 1 ]; then
		echo -e "main: TARGET=$TARGET."
	    fi
	    ;;
	"vrsn")
	    shift
	    VPATH="$1"
	    if [ $VRBS -eq 1 ]; then
		echo -e "main: VPATH=$VPATH."
	    fi
	    ;;
	"hst")
	    shift
	    RHOST="$1"
	    if [ $VRBS -eq 1 ]; then
		echo -e "main: RHOST=$RHOST."
	    fi
	    ;;
	*)
	    if [ $VRBS -eq 1 ]; then
		echo -e "main: no double shift needed."
	    fi
	;;
    esac
    NEXTVAR=""
    shift
done

if [ $VRBS -eq 1 ]; then
    echo 
    echo -e "the files path are:"
    echo -e "~/$PREPATH/$VPATH for HTML reports"
    echo -e "~/$LOGPATH for log files"    
    echo -e "full ID: $USER@$RHOST"
fi
echo -e "extracting reports from $USER@$RHOST:/home/test/$PREPATH/$VPATH"
echo -e "extracting log files from $USER@$RHOST:/home/test/$LOGPATH"
echo -e "Looking for files generated on: $MONTHN / $DAY"
echo -e "Target directory/folder: $TARGET\n"

#start looking for the candidate files in the server-path indicated.
HTMLF=$(echo $(ssh -q -t $USER@$RHOST <<ENDSSH
    ls -ltr ~/$PREPATH/$VPATH/*.html | grep "$MONTHN $DAY"
ENDSSH
     ) | awk -F/home '{ 
	     i=2 
	     while (i <= NF) { 
	     	   print $i
		   i=i+1 } 
	     }')
LOGF=$(echo $(ssh -q -t $USER@$RHOST <<ENDSSH
    ls -ltr ~/$LOGPATH/test*.log | grep "$MONTHN $DAY"
ENDSSH
     ) | awk -F/home '{ 
	     i=2 
	     while (i <= NF) { 
	     	   print $i
		   i=i+1 } 
	     }')

echo -e "\nSelecting Files:"
SFILE=$(echo -e "$HTMLF" | awk -F" " 'BEGIN {ORS="\n"} {
	     i=1
	     while (i <= NF) {
	     if (index($i, "est/")!=0)
	     	print $i
	     i=i+1 }
	     }')
echo -e $SFILE
SLFILE=$(echo -e "$LOGF" | awk -F" " 'BEGIN {ORS="\n"} {
	     i=1
	     while (i <= NF) {
	     if (index($i, "est/")!=0)
	     	print $i
	     i=i+1 }
	     }')
echo -e $SLFILE

#verify that the correct target directory is used
verifytarget
echo -e "\n"

####
#Make sure we can use sftp to move the files to the common area.
#Send to screen what will happen.
####
if [ -z "$GSAID" ] || [ -z "$SSHPASS" ]; then
    echo -e "Not transfering reports to GSA"
    echo -e "GSAID or SSHPASS environment variables is missing\n"
    TRSFRGSA="0"
else
    echo -e "Moving reports and logs to the next GSA area:"
    echo -e "$GSAID:$GSADIR"
fi

#####
# If posible start transfering all the selected files
# Start with the html reports.
#####
#set -x
if [ "$TRSFRGSA" == "1" ]; then
    if [ "$SFILE" == "" ]; then
	echo -e "There are no reports to transfer yet, please try later"
    else
	echo -e "starting report(s) transfer"
	for i in $SFILE
	do
	    echo -e "Tranfering report:"
	    echo -e $i
	    echo -e "to: $TARGET"
	    scp -p $USER@$RHOST":/home"$i $TARGET
	    echo put $TARGET"/"${i##*/} | sshpass -e sftp $GSAID":"$GSADIR
	done
  
    fi
#####
# Transfer logs
#####
    if [ "$SLFILE" == "" ]; then
	echo -e "there are no logs files to transfer yet, please try later"
    else
	echo -e "starting log(s) transfer"
	for i in $SLFILE
	do
	    echo -e "Tranfering log:"
	    echo -e $i
	    echo -e "to: $TARGET"
	    scp -p $USER@$RHOST":/home"$i $TARGET
	    echo put $TARGET"/"${i##*/} | sshpass -e sftp $GSAID":"$GSADIR    
	done
    fi
fi
#set +x
echo -e "\n\n*********DONE*********"
exit 0
