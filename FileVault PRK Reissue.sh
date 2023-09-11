#!/bin/bash

####################################################################################################
#
# Reissue FileVault Recovery Key via Dialog
#
# This script uses swiftDialog to present the end-user
# a prompt for their password in effort to reissue a 
# FileVault recovery key. The key is then escrowed to
# Jamf Pro. This script calls for a Jamf recon, so no need
# to add it as a maintenance payload on your policy. 
#
# Downloads and installs swiftDialog if it doesn't already
# exist on the computer.
#
# Exit Codes:
#	0: Clean Exit
#	1: Script Not Run As Root
#	2: OS less than version 10.9
#	3: Remote Users Logged In
#	4: FileVault Encryption Not Completed, Not Enabled, or Not Verified; check logs
#	5: Finder or Dock not running; user not at desktop
#	6: Logged in system account
#	7: FileVault Redirection Key not installed
#
#
####################################################################################################
#
# HISTORY
#
#   Version 1.0.0, 01.03.2023, Robert Schroeder (@robjschroeder)
#	- Script created
#
#   Version 1.3.0, 05.17.2023, Robert Schroeder (@robjschroeder)
#	- Script rewrite to align with other scripts hosted within my GitHub Repos
#	- Verifying Escrow to Jamf Pro capability
#
#   Version 1.4.0, 09.11.2023, Robert Schroeder (@robjschroeder)
#	- Updated swiftDialog download link
#
####################################################################################################

####################################################################################################
#
# Global Variables
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Version and Jamf Pro Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

scriptVersion="1.3.0"
scriptFunctionalName="FileVault PRK Reissue"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

scriptLog="${4:-"/var/log/com.company.log"}"        # Parameter 4: Script Log Location [ /var/log/com.company.log ] (i.e., Your organization's default location for client-side logs)
banner="${5:-"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRgKEFxRXAMU_VCzaaGvHKkckwfjmgGncVjA&usqp=CAU"}"
infotext="${6:-"More Information"}"
infolink="${7:-"https://support.apple.com/en-us/HT204837"}"
icon="${8:-"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns"}"
supportInformation="${9:-"support@organization.com"}"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Various Feature Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #


### Messaging Variables ###

orgName="lululemon Athletica"
message="## FileVault Recovery Key Update\n\n${orgName} uses macOS FileVault encryption to ensure your data is protected. The recovery key for this encryption is used if you ever get locked out of your Mac.\n\n We have discovered a problem with your existing recovery key. Please sign in below to rotate and store a new recovery key."
forgotMessage="## FileVault Recovery Key Update\n\n${orgName} uses macOS FileVault encryption to ensure your data is protected. The recovery key for this encryption is used if you ever get locked out of your Mac.\n\n We have discovered a problem with your existing recovery key. Please sign in below to rotate and store a new recovery key.\n\n ### Password Incorrect please try again:"
FAIL_MESSAGE="## Please check your password and try again.\n\nIf issue persists, please contact support: ${supportInformation}."

### SwiftDialog  Variables ###

dialogApp="/usr/local/bin/dialog"
dialogCommandFile=$( mktemp -u /var/tmp/dialogCommand.XXX )

# Main dialog
dialogCMD="$dialogApp \
--title \"none\" \
--bannerimage \"$banner\" \
--message \"$message\" \
--button1text \"Submit\" \
--icon \"$icon\" \
--infobuttontext \"$infotext\" \
--infobuttonaction \"$infolink\" \
--messagefont 'size=14' \
--position 'centre' \
--ontop \
--moveable \
--textfield \"Enter Password\",secure,required \
--commandfile \"$dialogCommandFile\" "

# Forgot password dialog
dialogForgotCMD="$dialogApp \
--title \"none\" \
--bannerimage \"$banner\" \
--message \"$forgotMessage\" \
--button1text \"Submit\" \
--icon \"$icon\" \
--infobuttontext \"$infotext\" \
--infobuttonaction \"$infolink\" \
--messagefont 'size=14' \
--position 'centre' \
--ontop \
--moveable \
--textfield \"Enter Password\",secure,required \
--commandfile \"$dialogCommandFile\" "

# Error dialog
dialogError="$dialogApp \
--title \"none\" \
--bannerimage \"$banner\" \
--message \"$FAIL_MESSAGE\" \
--button1text \"Close\" \
--infotext \"$scriptVersion\" \
--messagefont 'size=14' \
--position 'centre' \
--ontop \
--moveable \
--commandfile \"$dialogCommandFile\" "

# Success Dialog
dialogSuccess="$dialogApp \
--title \"none\" \
--image \"https://github.com/unfo33/venturewell-image/blob/main/a-hand-drawn-illustration-of-thank-you-letter-simple-doodle-icon-illustration-in-for-decorating-any-design-free-vector.jpeg?raw=true\" \
--imagecaption \"Your FileVault Recovery Key was successfully stored!\" \
--bannerimage \"$banner\" \
--button1text \"Close\" \
--infotext \"$scriptVersion\" \
--messagefont 'size=14' \
--position 'centre' \
--ontop \
--moveable \
--commandfile \"$dialogCommandFile\" "

# Optional but recommended: The profile identifiers of the FileVault Key
# Redirection profiles (e.g. ABCDEF12-3456-7890-ABCD-EF1234567890).
PROFILE_IDENTIFIER_10_12="" # 10.12 and earlier
PROFILE_IDENTIFIER_10_13="931CB565-285B-4C7C-83BC-C25E94DEDDE3" # 10.13 and later

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Operating System, Computer Model Name, etc.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

osVersion=$( sw_vers -productVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )
osMinorVersion=$( echo "${osVersion}" | awk -F '.' '{print $2}' )
fvStatus=$( /usr/bin/fdesetup status )
finderPID=$( /usr/bin/pgrep -x "Finder" )
dockPID=$( /usr/bin/pgrep -x "Dock" )

####################################################################################################
#
# Pre-flight Checks
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${scriptLog}" ]]; then
	touch "${scriptLog}"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Script Logging Function
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
	echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Current Logged-in User Function
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function currentLoggedInUser() {
	loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
	updateScriptLog "PRE-FLIGHT CHECK: Current Logged-in User: ${loggedInUser}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "\n\n###\n# ${scriptFunctionalName} (${scriptVersion})\n# \n###\n"
updateScriptLog "PRE-FLIGHT CHECK: Initiating …"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(id -u) -ne 0 ]]; then
	updateScriptLog "PRE-FLIGHT CHECK: This script must be run as root; exiting."
	exit 1
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate OS is greater than 10.9
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "$osMajorVersion" -eq 10 && "$osMinorVersion" -lt 9 ]]; then
	updateScriptLog "PRE-FLIGHT CHECK: OS needs to be 10.9 or greater; exiting..."
	exit 2
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm Dock is running / user is at Desktop
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Check Finder Process
if [ -z "${finderPID}" ]; then
	updateScriptLog "PRE-FLIGHT CHECK: Finder is not running; exiting..."
	exit 5
else
	updateScriptLog "PRE-FLIGHT CHECK: Finder is running with PID: $finderPID"
fi

# Check Dock Process
if [ -z "${dockPID}" ]; then
	updateScriptLog "PRE-FLIGHT CHECK: Dock is not running; exiting..."
	exit 5
else
	updateScriptLog "PRE-FLIGHT CHECK: Dock is running with PID: $dockPID"
fi

updateScriptLog "PRE-FLIGHT CHECK: Finder & Dock are running; proceeding …"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Logged-in System Accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "PRE-FLIGHT CHECK: Check for Logged-in System Accounts …"
currentLoggedInUser

if { [[ "${loggedInUser}" = "_mbsetupuser" ]] || [[ "${loggedInUser}" = "loginwindow" ]] ; } ; then
	
	updateScriptLog "PRE-FLIGHT CHECK: Logged-in User is ${loggedInUser}; exiting...."
	exit 6
fi

loggedInUserFullname=$( id -F "${loggedInUser}" )
loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print toupper(substr($0,1,1))substr($0,2)}' )
loggedInUserID=$( id -u "${loggedInUser}" )
loggedInUserUUID=$(dscl . -read /Users/"$loggedInUser"/ GeneratedUID | awk '{print $2}')
updateScriptLog "PRE-FLIGHT CHECK: Current Logged-in User First Name: ${loggedInUserFirstname}"
updateScriptLog "PRE-FLIGHT CHECK: Current Logged-in User ID: ${loggedInUserID}"
updateScriptLog "PRE-FLIGHT CHECK: Current Logged-in User UUID ${loggedInUserUUID}"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate no remote users logged in
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Check for remote users.
remoteUsers=$(/usr/bin/who | /usr/bin/grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | wc -l)
if [[ $remoteUsers -gt 0 ]]; then
	updateScriptLog "PRE-FLIGHT: Remote users logged in; exiting"
	exit 3
else
	updateScriptLog "PRE-FLIGHT: No Remote users logged in; proceeding..."
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogCheck() {
	
	# Get the URL of the latest PKG From the Dialog GitHub repo
	dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	
	# Expected Team ID of the downloaded PKG
	expectedDialogTeamID="PWA5E9TQ59"
	
	# Check for Dialog and install if not found
	if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
		
		updateScriptLog "PRE-FLIGHT CHECK: Dialog not found. Installing..."
		
		# Create temporary working directory
		workDirectory=$( /usr/bin/basename "$0" )
		tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )
		
		# Download the installer package
		/usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"
		
		# Verify the download
		teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
		
		# Install the package if Team ID validates
		if [[ "$expectedDialogTeamID" == "$teamID" ]]; then
			
			/usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
			sleep 2
			dialogVersion=$( /usr/local/bin/dialog --version )
			updateScriptLog "PRE-FLIGHT CHECK: swiftDialog version ${dialogVersion} installed; proceeding..."
			
		else
			
			# Display a so-called "simple" dialog if Team ID fails to validate
			osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "'"${scriptFunctionalName}"': Error" buttons {"Close"} with icon caution'
			quitScript
			
		fi
		
		# Remove the temporary working directory when done
		/bin/rm -Rf "$tempDirectory"
		
	else
		
		updateScriptLog "PRE-FLIGHT CHECK: swiftDialog version $(/usr/local/bin/dialog --version) found; proceeding..."
		
	fi
	
}

if [[ ! -e "/Library/Application Support/Dialog/Dialog.app" ]]; then
	dialogCheck
else
	updateScriptLog "PRE-FLIGHT CHECK: swiftDialog version $(/usr/local/bin/dialog --version) found; proceeding..."
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Check Encryption Status
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if /usr/bin/grep -q "Encryption in progress" <<< "$fvStatus"; then
	updateScriptLog "PRE-FLIGHT: FileVault encryption is in progress. Please run the script again when it finishes."
	exit 4
elif /usr/bin/grep -q "FileVault is Off" <<< "$fvStatus"; then
	updateScriptLog "PRE-FLIGHT: Encryption is not active."
	exit 4
elif ! /usr/bin/grep -q "FileVault is On" <<< "$fvStatus"; then
	updateScriptLog "PRE-FLIGHT: Unable to determine encryption status."
	exit 4
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate OS and redirection profiles
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# If specified, the FileVault key redirection profile needs to be installed.
if [[ "$osMajorVersion" -eq 10 && "$osMinorVersion" -le 12 ]]; then
	if [[ "$PROFILE_IDENTIFIER_10_12" != "" ]]; then
		if ! /usr/bin/profiles -Cv | /usr/bin/grep -q "profileIdentifier: $PROFILE_IDENTIFIER_10_12"; then
			updateScriptLog "PRE-FLIGHT CHECK: The FileVault Key Redirection profile is not yet installed on $osVersion; exiting..."
			exit 7
		fi
	fi
elif [[ "$osMajorVersion" -eq 10 && "$osMinorVersion" -gt 12 ]]; then
	if [[ "$PROFILE_IDENTIFIER_10_13" != "" ]]; then
		if ! /usr/bin/profiles -Cv | /usr/bin/grep -q "profileIdentifier: $PROFILE_IDENTIFIER_10_13"; then
			updateScriptLog "PRE-FLIGHT CHECK: The FileVault Key Redirection profile is not yet installed on $osVersion; exiting..."
			exit 7
		fi
	fi
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Complete
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "PRE-FLIGHT CHECK: Complete"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FileVault PRK Reissue: Prepare for PRK Reissue
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Suppress errors for the duration of this script. (This prevents JAMF Pro from
# marking a policy as "failed" if the words "fail" or "error" inadvertently
# appear in the script output.)
exec 2>/dev/null

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FileVault PRK Reissue: Prompt User For Password
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Display a branded prompt explaining the password prompt.
updateScriptLog "${scriptFunctionalName}: Alerting user $loggedInUser about incoming password prompt..."
userPass=$(eval "$dialogCMD" | grep "Enter Password" | awk -F " : " '{print $NF}')

# Thanks to James Barclay (@futureimperfect) for this password validation loop.
TRY=1
until /usr/bin/dscl /Search -authonly "$loggedInUser" "${userPass}" &>/dev/null; do
	(( TRY++ ))
	updateScriptLog "${scriptFunctionalName}: Prompting $loggedInUser for their Mac password (attempt $TRY)..."
	userPass=$(eval "$dialogForgotCMD" | grep "Enter Password" | awk -F " : " '{print $NF}')
	if (( TRY >= 5 )); then
		updateScriptLog "${scriptFunctionalName}: [ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
		eval "$dialogError"
		rm -rf "$dialogCommandFile"
		exit 1
	fi
done
updateScriptLog "${scriptFunctionalName}: Successfully prompted for Mac password."

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FileVault PRK Reissue: Unload FDERecoveryAgent LaunchDaemon if needed
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if /bin/launchctl list | /usr/bin/grep -q "com.apple.security.FDERecoveryAgent"; then
	updateScriptLog "${scriptFunctionalName}: Unloading FDERecoveryAgent LaunchDaemon..."
	/bin/launchctl unload /System/Library/LaunchDaemons/com.apple.security.FDERecoveryAgent.plist
fi

if pgrep -q "FDERecoveryAgent"; then
	updateScriptLog "${scriptFunctionalName}: Stopping FDERecoveryAgent process..."
	killall "FDERecoveryAgent"
fi

# Translate XML reserved characters to XML friendly representations. (Thanks @elliot jordan)
userPass=${userPass//&/&amp;}
userPass=${userPass//</&lt;}
userPass=${userPass//>/&gt;}
userPass=${userPass//\"/&quot;}
userPass=${userPass//\'/&apos;}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FileVault PRK Reissue: Mac OS 10.13 store last modification date
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "$osMajorVersion" -ge 11 ]] || [[ "$osMajorVersion" -eq 10 && "$osMinorVersion" -ge 13 ]]; then
	updateScriptLog "${scriptFunctionalName}: Checking for /var/db/FileVaultPRK.dat on macOS 10.13+..."
	PRKMod=0
	if [ -e "/var/db/FileVaultPRK.dat" ]; then
		updateScriptLog "${scriptFunctionalName}: Found existing personal recovery key."
		PRKMod=$(/usr/bin/stat -f "%Sm" -t "%s" "/var/db/FileVaultPRK.dat")
	fi
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FileVault PRK Reissue: Issue New Recovery Key
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "${scriptFunctionalName}: Issuing new recovery key..."
fdeSetupOutput="$(/usr/bin/fdesetup changerecovery -norecoverykey -verbose -personal -inputplist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Username</key>
	<string>$loggedInUser</string>
	<key>Password</key>
	<string>$userPass</string>
</dict>
</plist>
EOF
)"

# Test success conditions.
fdeSetupResult=$?

# Clear password variable.
unset "$userPass"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FileVault PRK Reissue: Validate Success of PRK Reissue
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Differentiate <=10.12 and >=10.13 success conditions
if [[ "$osMajorVersion" -ge 11 ]] || [[ "$osMajorVersion" -eq 10 && "$osMinorVersion" -ge 13 ]]; then
	# Check new modification time of of FileVaultPRK.dat
	escrowStatus=1
	if [ -e "/var/db/FileVaultPRK.dat" ]; then
		newPRKMod=$(/usr/bin/stat -f "%Sm" -t "%s" "/var/db/FileVaultPRK.dat")
		if [[ $newPRKMod -gt $PRKMod ]]; then
			escrowStatus=0
			updateScriptLog "${scriptFunctionalName}: Recovery key updated locally and available for collection via MDM. (This usually requires two 'jamf recon' runs to show as valid.)"
		else
			updateScriptLog "${scriptFunctionalName}: [WARNING] The recovery key does not appear to have been updated locally."
		fi
	fi
else
	# Check output of fdesetup command for indication of an escrow attempt
	/usr/bin/grep -q "Escrowing recovery key..." <<< "$fdeSetupOutput"
	escrowStatus=$?
fi

if [[ $fdeSetupResult -ne 0 ]]; then
	[[ -n "$fdeSetupOutput" ]] && echo "$fdeSetupOutput"
	updateScriptLog "${scriptFunctionalName}: [WARNING] fdesetup exited with return code: $fdeSetupResult"
	updateScriptLog "${scriptFunctionalName}: See this page for a list of fdesetup exit codes and their meaning:"
	updateScriptLog "${scriptFunctionalName}: https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man8/fdesetup.8.html"
	updateScriptLog "${scriptFunctionalName}: Displaying \"failure\" message..."
	eval "$dialogError"
	rm -rf "$dialogCommandFile"
elif [[ $escrowStatus -ne 0 ]]; then
	[[ -n "$fdeSetupOutput" ]] && echo "$fdeSetupOutput"
	updateScriptLog "${scriptFunctionalName}: [WARNING] FileVault key was generated, but escrow cannot be confirmed. Please verify that the redirection profile is installed and the Mac is connected to the internet."
	updateScriptLog "${scriptFunctionalName}: Displaying \"failure\" message..."
	eval "$dialogError"
	rm -rf "$dialogCommandFile"
else
	[[ -n "$fdeSetupOutput" ]] && echo "$fdeSetupOutput"
	updateScriptLog "${scriptFunctionalName}: Displaying \"success\" message..."
	# Initiate one Jamf Recon
	/usr/local/bin/jamf recon
	eval "$dialogSuccess"
	rm -rf "$dialogCommandFile"
fi

rm -rf "$dialogCommandFile"

updateScriptLog "${scriptFunctionalName}: Exiting ${fdeSetupResult}"
exit $fdeSetupResult
