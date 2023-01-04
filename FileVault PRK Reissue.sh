#!/bin/bash

# This script uses swiftDialog to present the end-user
# a prompt for their password in effort to reissue a 
# FileVault recovery key. The key is then escrowed to
# Jamf Pro. This script calls for a Jamf recon, so no need
# to add it as a maintenance payload on your policy. 
#
# Downloads and installs swiftDialog if it doesn't already
# exist on the computer.
#
# Created 01.03.2023 @robjschroeder
# Script Version: 1.2.0
# Last Modified: 01.03.2023

##################################################
# Variables -- edit as needed

# Script Version
scriptVersion="1.2.0"
# Banner image for message
banner="${4:-"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRgKEFxRXAMU_VCzaaGvHKkckwfjmgGncVjA&usqp=CAU"}"
# More Information Button shown in message
infotext="${5:-"More Information"}"
infolink="${6:-"https://support.apple.com/en-us/HT204837"}"
# Swift Dialog icon to be displayed in message
icon="${7:-"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns"}"
supportInformation="${8:-"support@organization.com"}"
## SwiftDialog
dialogApp="/usr/local/bin/dialog"

# Messages shown to the user in the dialog when prompting for password
message="## FileVault Recovery Key\n\nYour FileVault Recovery Key is currently not being stored. This key is important to help prevent unauthorized access to the information on your computer.\n\n Please enter your Mac password to store your FileVault Recovery Key."
forgotMessage="## FileVault Recovery Key\n\nYour FileVault Recovery Key is currently not being stored. This key is important to help prevent unauthorized access to the information on your computer.\n\n ### Password Incorrect please try again:"

# The body of the message that will be displayed if a failure occurs.
FAIL_MESSAGE="## Please check your password and try again.\n\nIf issue persists, please contact support: $supportInformation."

# Main dialog
dialogCMD="$dialogApp \
--title \"none\" \
--bannerimage \"$banner\" \
--message \"$message\" \
--button1text \"Submit\" \
--icon "${icon}" \
--infobuttontext \"${infotext}\" \
--infobuttonaction "${infolink}" \
--messagefont 'size=14' \
--position 'centre' \
--ontop \
--moveable \
--textfield \"Enter Password\",secure,required"

# Forgot password dialog
dialogForgotCMD="$dialogApp \
--title \"none\" \
--bannerimage \"$banner\" \
--message \"$forgotMessage\" \
--button1text \"Submit\" \
--icon "${icon}" \
--infobuttontext \"${infotext}\" \
--infobuttonaction "${infolink}" \
--messagefont 'size=14' \
--position 'centre' \
--ontop \
--moveable \
--textfield \"Enter Password\",secure,required"

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
--moveable \ "

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
--moveable \ "

#
##################################################
# Script work -- do not edit below here

# Validate swiftDialog is installed
if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
	echo "Dialog not found, installing..."
	dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	expectedDialogTeamID="PWA5E9TQ59"
	# Create a temp directory
	workDir=$(/usr/bin/basename "$0")
	tempDir=$(/usr/bin/mktemp -d "/private/tmp/$workDir.XXXXXX")
	# Download latest version of swiftDialog
	/usr/bin/curl --location --silent "$dialogURL" -o "$tempDir/Dialog.pkg"
	# Verify download
	teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDir/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
	if [ "$expectedDialogTeamID" = "$teamID" ] || [ "$expectedDialogTeamID" = "" ]; then
		/usr/sbin/installer -pkg "$tempDir/Dialog.pkg" -target /
	else
		echo "Team ID verification failed, could not continue..."
		exit 6
	fi
	/bin/rm -Rf "$tempDir"
else
	echo "Dialog v$(dialog --version) installed, continuing..."
fi

# Get the logged in user's name
userName=$(/bin/echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/&&!/loginwindow/{print $3}')

## Grab the UUID of the User
userNameUUID=$(dscl . -read /Users/$userName/ GeneratedUID | awk '{print $2}')

## Get the OS build
BUILD=$(/usr/bin/sw_vers -buildVersion | awk {'print substr ($0,0,2)'})

# Exits if root is the currently logged-in user, or no logged-in user is detected.
function check_logged_in_user {
	if [ "$userName" = "root" ] || [ -z "$currentuser" ]; then
		echo "Nobody is logged in."
		exit 0
	fi
}

## This first user check sees if the logged in account is already authorized with FileVault 2
userCheck=$(fdesetup list | awk -v usrN="$userNameUUID" -F, 'match($0, usrN) {print $1}')
if [ "${userCheck}" != "${userName}" ]; then
	echo "This user is not a FileVault 2 enabled user."
	eval "$dialogError"
    exit 3
fi

## Counter for Attempts
try=0
maxTry=2

## Check to see if the encryption process is complete
encryptCheck=$(fdesetup status)
statusCheck=$(echo "${encryptCheck}" | grep "FileVault is On.")
expectedStatus="FileVault is On."
if [ "${statusCheck}" != "${expectedStatus}" ]; then
	echo "The encryption process has not completed."
	echo "${encryptCheck}"
	"$dialogError"
    exit 4
fi

# Display a branded prompt explaining the password prompt.
echo "Alerting user $userName about incoming password prompt..."
userPass=$(eval "$dialogCMD" | grep "Enter Password" | awk -F " : " '{print $NF}')

# Thanks to James Barclay (@futureimperfect) for this password validation loop.
TRY=1
until /usr/bin/dscl /Search -authonly "$userName" "${userPass}" &>/dev/null; do
	(( TRY++ ))
	echo "Prompting $userName for their Mac password (attempt $TRY)..."
	userPass=$(eval "$dialogForgotCMD" | grep "Enter Password" | awk -F " : " '{print $NF}')
	if (( TRY >= 5 )); then
		echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
		eval "$dialogError"
		exit 1
	fi
done
echo "Successfully prompted for Mac password."

if [[ $BUILD -ge 13 ]] &&  [[ $BUILD -lt 17 ]]; then
	## This "expect" block will populate answers for the fdesetup prompts that normally occur while hiding them from output
	result=$(expect -c "
log_user 0
spawn fdesetup changerecovery -personal
expect \"Enter a password for '/', or the recovery key:\"
send {${userPass}}   
send \r
log_user 1
expect eof
" >> /dev/null)
			elif [[ $BUILD -ge 17 ]]; then
			result=$(expect -c "
log_user 0
spawn fdesetup changerecovery -personal
expect \"Enter the user name:\"
send {${userName}}   
send \r
expect \"Enter a password for '/', or the recovery key:\"
send {${userPass}}   
send \r
log_user 1
expect eof
")
					else
					echo "OS version not 10.9+ or OS version unrecognized"
					echo "$(/usr/bin/sw_vers -productVersion)"
					exit 5
					fi
					sleep 30
					echo "Recovery Key reissued for user: $userName, running recon now..."
					sudo jamf recon
					eval "$dialogSuccess"
					exit 0
