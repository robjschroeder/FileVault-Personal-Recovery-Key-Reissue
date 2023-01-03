# FileVault Personal Recovery Key Reissue
![GitHub release (latest by date)](https://img.shields.io/github/v/release/robjschroeder/FileVault-Personal-Recovery-Key-Reissue?display_name=tag)

This script will provide a user interface for reissuing a FileVault Personal Recovery Key. This is helpful if a computer is already encrypted but the recovery key is not escrowed within Jamf Pro. The script uses swiftDialog to present the dialog to the user: [https://github.com/bartreardon/swiftDialog](https://github.com/bartreardon/swiftDialog)
![Screenshot 2023-01-03 at 2 25 55 PM](https://user-images.githubusercontent.com/23343243/210449773-1fec1696-8bc4-4c02-ab46-0c250d1f778b.png)

## Why build this
I started working with Bart's swiftDialog tool recently and saw the opportunity for this when I was asked about a FileVault PRK Reissue script. I tested the FV script on a Ventura 13.1 computer to validate that it still worked for the new OS and then thought "swiftDialog would make this better" I also recently saw in MacAdmins Slack a similar project that an admin was able to use for setting the boot level of a Mac and delivering the message to the user via swiftDialog. 

Then began my task of creating a user friendly dialog for the purpose of reissuing a PRK using swiftDialog...

## How to use
1. Add the FileVault PRK Reissue.sh script into your Jamf Pro
2. Create a new policy in Jamf Pro, scoped to computers that need a new key reissued
3. Add the script to your policy and fill out the following parameters:
- Parameter 4: Link to a banner image
- Parameter 5: "More Information" button text
- Parameter 6: "More Information" button link
- Parameter 7: Link to icon shown in dialog
- Parameter 8: Support's contact info, in case of failure.

If the target computer doesn't have swiftDialog, the script will curl the latest version and install it before continuing. 

The policy can then be ran on the computers that need it, preferably in Self Service so they will be expecting it...

Validated on:
- Apple Intel Mac: macOS 13.1 Ventura
