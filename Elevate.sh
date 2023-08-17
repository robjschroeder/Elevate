#!/bin/bash
# shellcheck disable=SC2181

# https://github.com/robjschroeder/Elevate
#
# Script to promote the logged in user to admin then demote 
# back to standard user after a specified number of seconds
#
# Created 02.23.2023 @robjschroeder
# Updated 03.10.2023 @robjschroeder
# 
# Updated 03.12.2023 @dan-snelson
# - Added variables for:
#	- Script Version
#	- Reverse Domain Name Notation (i.e., plistDomain)
#	  - Used for client-side logs
#	- Elevation Duration
# - Added logging for loggedInUser's group membership
# - Visual tweaks to user dialog
# 
# Updated 03.14.2023 @robjschroeder
# - Changed Parameter 5 variable value and name 
# - Added scriptLog as a concatenation of Parameter 5 + Parameter 4
#
# Updated 04.22.2023 @robjschroeder
# - Added line to collect log archive for activity duration. Log will be created at /private/var/log/elevateLog-${timestamp}.logarchive
# - Logging using macOS log binary
#
# Updated 05.08.2023 @dan-snelson
# - Execute a Jamf Pro policy trigger (Parameter 6)
#
# Updated 07.10.2023 @robjschroeder
# # # Version 2.0.0-b1 # # #
# - Elevate now prompts for a reason for Elevation, this value gets stored in an array in the Elevate plist located at /Library/Preferences/xyz.techitout.elevate.plist
# - Elevate now checks for admin status prior to elevation happening, this can help to prevent admin users from losing their admin status. 
# - Elevate can now use a managed configuration profile sent from MDM, a JSON schema is currently being worked on
# -- Use this in conjunction with the `removeAdminRights` variable for desired results.
# - Extension Attribute examples coming soon. 
#
# Updated 07.10.2023 @robjschroeder
# Version: 2.0.0-b2
# - Fixed some issues with plist entries
#
# Updated 07.11.2023 @robjschroeder
# Version: 2.0.0-b3
# - Added functionality for Slack and Teams webhooks
# - Additional cleanup
#
# Updated 07.20.2023 @robjschroeder
# Version: 2.0.1
# - Added a cancel button for Elevate request. FR #18 (thanks @dan-snelson!)
# - Modified prompt dialog to be ontop when request is made
#
# Updated 07.24.2023 @robjschroeder
# Version: 2.0.2
# - Moved initial recon for improved launch speed. Issue #20 (thanks @dan-snelson!)
# - Added script version to infobox text of prompt dialog (thanks @dan-snelson!)
# - Webhook data is no longer shown in log when processing (good eye @dan-snelson!)
# - Added function to disable jamf pro binary during elevation. Issue #21 (thanks @dan-snelson!)
#
# Updated 07.24.2023 @robjschroeder
# Version: 2.0.3
# - Addressed an issue with using script parameters after a managed configuration profile is removed
# - Removed ComputerID from PLIST, no need
# - WebhookURL should not be stored in PLIST, it will now be removed after it is used
#
# Updated 07.27.2023 @robjschroeder
# Version: 2.0.4
# - Silenced the output of the creation of the Launch Daemon to declutter Jamf Pro policy logs (thanks @dan-snelson!)
#
# Updated 08.17.2023 @dan-snelson
# Version 2.0.5
# - Added permissions correction on `mktemp`-created files (for swiftDialog 2.3)
#
##################################################

####################################################################################################
#
# Global Variables
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Version and Jamf Pro Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

scriptVersion="2.0.5"
scriptFunctionalName="Elevate"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Parameter 4: Reverse Domain Name Notation (i.e., "xyz.techitout")
plistDomain="${4:-"com.company"}"
# Script Log Location (based on $plistDomain)
scriptLog="/var/log/${plistDomain}.log"

# Parameter 5: Maximum Elevation Duration (in minutes)
elevationDurationMinutes="${5:-"10"}"

# Parameter 6: Execute a Jamf Pro Policy
jamfProPolicyCustomEvent="${6:-"localAdministrativeRightsRemove"}"

# Parameter 7: Remove administrator privileges if user is already admin
removeAdminRights="${7:-"true"}"

# Paramter 8: Microsoft Teams or Slack Webhook URL [ Leave blank to disable (default) | https://microsoftTeams.webhook.com/URL | https://hooks.slack.com/services/URL ] Can be used to send Elevation request details to Microsoft Teams or Slack via Webhook. (Function will automatically detect if Webhook URL is for Slack or Teams; can be modified to include other communication tools that support functionality.)
webhookURL="${8:-""}"


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Various Feature Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Dialog Icon
icon="/System/Library/CoreServices/KeyboardSetupAssistant.app/Contents/Resources/AppIcon.icns"

# IT Support Variables - Use these if the default text is fine but you want your org's info inserted instead
supportTeamName="Help Desk"
supportTeamPhone="+1 (801) 555-1212"
supportTeamEmail="support@domain.org"
supportKB="KB86753099"
supportTeamErrorKB=", and mention [${supportKB}](https://servicenow.company.com/support?id=kb_article_view&sysparm_article=${supportKB}#Failures)"
supportTeamHelpKB="\n- **Knowledge Base Article:** ${supportKB}"

# Path to PList Buddy
plistBuddy="/usr/libexec/PlistBuddy"

# Jamf Binary
jamfBinary="/usr/local/bin/jamf"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Operating System, Computer Model Name, etc.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

osVersion=$( sw_vers -productVersion )
osVersionExtra=$( sw_vers -productVersionExtra ) 
osBuild=$( sw_vers -buildVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )
if [[ -n $osVersionExtra ]] && [[ "${osMajorVersion}" -ge 13 ]]; then osVersion="${osVersion} ${osVersionExtra}"; fi # Report RSR sub version if applicable

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
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Current Logged-in User: ${loggedInUser}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "\n\n###\n# ${scriptFunctionalName} (${scriptVersion})\n# https://techitout.xyz\n###\n"
updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Initiating …"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(id -u) -ne 0 ]]; then
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}: This script must be run as root; exiting."
    exit 1
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm Dock is running / user is at Desktop
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if pgrep -q -x "Finder" && pgrep -q -x "Dock"; then
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Finder & Dock are running; proceeding …"
else
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Finder & Dock are not running; exiting …"
    exit 1
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Logged-in System Accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "PRE-FLIGHT CHECK: Check for Logged-in System Accounts …"
currentLoggedInUser

loggedInUserFullname=$( id -F "${loggedInUser}" )
loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print toupper(substr($0,1,1))substr($0,2)}' )
loggedInUserID=$( id -u "${loggedInUser}" )
updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Current Logged-in User First Name: ${loggedInUserFirstname}"
updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Current Logged-in User ID: ${loggedInUserID}"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Operating System Version
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Since swiftDialog requires at least macOS 11 Big Sur, first confirm the major OS version
if [[ "${osMajorVersion}" -ge 11 ]] ; then
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): macOS ${osMajorVersion} installed; continuing ..."
else
    # The Mac is running an operating system older than macOS 11 Big Sur; exit with error
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): swiftDialog requires at least macOS 11 Big Sur and this Mac is running ${osVersion} (${osBuild}), exiting with error."
    osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\rExpected macOS 11 Big Sur (or newer), but found macOS '"${osVersion}"'.\r\r" with title "'${scriptFunctionalName}': Detected Outdated Operating System" buttons {"Open Software Update"} with icon caution'
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Executing /usr/bin/open '/System/Library/CoreServices/Software Update.app' …"
    su - "${loggedInUser}" -c "/usr/bin/open /System/Library/CoreServices/Software Update.app"
    exit 1
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogCheck() {

    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    # Check for Dialog and install if not found
    if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then

        updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Dialog not found. Installing..."

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
            updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): swiftDialog version ${dialogVersion} installed; proceeding..."

        else

            # Display a so-called "simple" dialog if Team ID fails to validate
            osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "'${scriptFunctionalName}': Error" buttons {"Close"} with icon caution'
            updateScriptLog "PRE-FLIGHT CHECK: Team ID validation failure, exiting..."
            exit 1
            
        fi

        # Remove the temporary working directory when done
        /bin/rm -Rf "$tempDirectory"

    else

        updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): swiftDialog version $(/usr/local/bin/dialog --version) found; proceeding..."

    fi

}

if [[ ! -e "/Library/Application Support/Dialog/Dialog.app" ]]; then
    dialogCheck
else
    updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): swiftDialog version $(/usr/local/bin/dialog --version) found; proceeding..."
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Cleanup Old Artifacts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Remove Elevate script
if [[ -f /var/tmp/elevate.sh ]]; then
	rm -rf /var/tmp/elevate.*
fi

# Delete the LaunchDaemon plist
if [[ -f /Library/LaunchDaemons/${plistDomain}.elevate.plist ]]; then
	/bin/rm "/Library/LaunchDaemons/${plistDomain}.elevate.plist"
fi

# Kill the LaunchDaemon process
/bin/launchctl remove "${plistDomain}".elevate

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Complete
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Complete"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Elevate: Create Preferences File for local Elevate Script
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #


# Check to see if preference file is being managed
elevateManagedConfigProfile="/Library/Managed Preferences/xyz.techitout.elevate.plist"
# PList to capture user input and house settings if not managed by MDM
elevateConfigProfile="/Library/Preferences/xyz.techitout.elevate.plist"

#Exit if there is no mobileconfig payload
managedConfig="false"
if [ -f "$elevateManagedConfigProfile" ]; then
	updateScriptLog "${scriptFunctionalName}: Managed Configuration Profile exists, assuming settings are set in this configuraiton profiles..."
    managedConfig="true"
    if [ -f "$elevateConfigProfile" ]; then
        updateScriptLog "${scriptFunctionalName}: Updating ${elevateConfigProfile} with extra variables..."
        ${plistBuddy} -c "Add :scriptVersion string ${scriptVersion}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :scriptVersion ${scriptVersion}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :scriptLog string ${scriptLog}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :scriptLog ${scriptLog}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :webhookURL string ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :webhookURL ${webhookURL}" ${elevateConfigProfile}
    else
        updateScriptLog "${scriptFunctionalName}: Creating ${elevateConfigProfile} with extra variables..."
        ${plistBuddy} -c "Add :scriptVersion string ${scriptVersion}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :scriptLog string ${scriptLog}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :webhookURL string ${webhookURL}" ${elevateConfigProfile}
    fi
else
    updateScriptLog "${scriptFunctionalName}: Managed Configuration Profile does not exist, using ${elevateConfigProfile} for settings"
fi

if [[ ${managedConfig} == "false" ]]; then
    updateScriptLog "${scriptFunctionalName}: Looking for ${elevateConfigProfile}"
    if [ -f "$elevateConfigProfile" ]; then
        updateScriptLog "${scriptFunctionalName}: ${elevateConfigProfile} already exists, no need to create"
        updateScriptLog "${scriptFunctionalName}: Updating ${elevateConfigProfile} to latest variables..."
        ${plistBuddy} -c "Add :scriptVersion string ${scriptVersion}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :scriptVersion ${scriptVersion}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :scriptLog string ${scriptLog}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :scriptLog ${scriptLog}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :webhookURL ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :webhookURL ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :elevationDurationMinutes string ${elevationDurationMinutes}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :elevationDurationMinutes ${elevationDurationMinutes}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :removeAdminRights bool ${removeAdminRights}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :removeAdminRights ${removeAdminRights}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :jamfProPolicyCustomEvent string ${jamfProPolicyCustomEvent}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :jamfProPolicyCustomEvent ${jamfProPolicyCustomEvent}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :webhookURL string ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :webhookURL ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :icon string ${icon}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :icon ${icon}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamName string ${supportTeamName}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :supportTeamName ${supportTeamName}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamPhone string ${supportTeamPhone}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :supportTeamPhone ${supportTeamPhone}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamEmail string ${supportTeamEmail}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :supportTeamEmail ${supportTeamEmail}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportKB string ${supportKB}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :supportKB ${supportKB}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamErrorKB string ${supportTeamErrorKB}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :supportTeamErrorKB ${supportTeamErrorKB}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamHelpKB string ${supportTeamHelpKB}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :supportTeamHelpKB ${supportTeamHelpKB}" ${elevateConfigProfile}
    else
        updateScriptLog "${scriptFunctionalName}: ${elevateConfigProfile} does not exist, creating now..."
        ${plistBuddy} -c "Add :scriptVersion string ${scriptVersion}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :scriptLog string ${scriptLog}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :webhookURL ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Set :webhookURL ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :elevationDurationMinutes string ${elevationDurationMinutes}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :removeAdminRights bool ${removeAdminRights}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :jamfProPolicyCustomEvent string ${jamfProPolicyCustomEvent}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :webhookURL string ${webhookURL}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :icon string ${icon}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamName string ${supportTeamName}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamPhone string ${supportTeamPhone}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamEmail string ${supportTeamEmail}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportKB string ${supportKB}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamErrorKB string ${supportTeamErrorKB}" ${elevateConfigProfile}
        ${plistBuddy} -c "Add :supportTeamHelpKB string ${supportTeamHelpKB}" ${elevateConfigProfile}
    fi
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Create the Elevate Script locally in /var/tmp
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

cat << '==endOfScript==' > /var/tmp/elevate.sh
#!/bin/bash
#set -x

# This is the local script that runs via LaunchDaemon to elevate the user

# Script Version, Script Log, Script Functional Name

scriptFunctionalName="Elevate"
scriptVersion=$( /usr/bin/defaults read /Library/Preferences/xyz.techitout.elevate.plist scriptVersion )
scriptLog=$( /usr/bin/defaults read /Library/Preferences/xyz.techitout.elevate.plist scriptLog )
webhookURL=$( /usr/bin/defaults read /Library/Preferences/xyz.techitout.elevate.plist webhookURL )

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin/
exitCode="0"

# Client-side logging
if [[ ! -f "${scriptLog}" ]]; then
	touch "${scriptLog}"
fi

# Client-side Script Logging Function (Thanks @dan-snelson!!)
function updateScriptLog() {
	echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

updateScriptLog "\n###\n# ${scriptFunctionalName} (${scriptVersion})\n# https://techitout.xyz/\n###\n"
updateScriptLog "Elevate Pre-flight: Initiating ..."

# Ensure computer does not go to sleep while running this script (thanks, @grahampugh!)

updateScriptLog "Elevate Pre-flight: Caffeinating this script (PID: $$)"
caffeinate -dimsu -w $$ &

# Determine if Managed Configuration Profile is being used
elevateProfilePath=""
if [ -f "/Library/Managed Preferences/xyz.techitout.elevate.plist" ]; then
	updateScriptLog "${scriptFunctionalName}: Managed Configuration Profile is defined and will be used"
	elevateProfilePath="/Library/Managed Preferences/xyz.techitout.elevate.plist"
else
	updateScriptLog "${scriptFunctionalName}: Continuing sans Managed Configuration Profile"
	elevateProfilePath="/Library/Preferences/xyz.techitout.elevate.plist"
fi

####################################################################################################
#
# Variables from configuration profile
#
####################################################################################################

updateScriptLog "${scriptFunctionalName}: Settings variables based on plist values"

elevationDurationMinutes=$( /usr/bin/defaults read "${elevateProfilePath}" elevationDurationMinutes )
icon=$( /usr/bin/defaults read "${elevateProfilePath}" icon )
jamfProPolicyCustomEvent=$( /usr/bin/defaults read "${elevateProfilePath}" jamfProPolicyCustomEvent )
removeAdminRights=$( /usr/bin/defaults read "${elevateProfilePath}" removeAdminRights )
supportKB=$( /usr/bin/defaults read "${elevateProfilePath}" supportKB )
supportTeamEmail=$( /usr/bin/defaults read "${elevateProfilePath}" supportTeamEmail )
supportTeamErrorKB=$( /usr/bin/defaults read "${elevateProfilePath}" supportTeamErrorKB )
supportTeamHelpKB=$( /usr/bin/defaults read "${elevateProfilePath}" supportTeamHelpKB )
supportTeamName=$( /usr/bin/defaults read "${elevateProfilePath}" supportTeamName )
supportTeamPhone=$( /usr/bin/defaults read "${elevateProfilePath}" supportTeamPhone)

####################################################################################################
#
# Dialog Variables
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# infobox-related variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

macOSproductVersion="$( sw_vers -productVersion )"
macOSbuildVersion="$( sw_vers -buildVersion )"
serialNumber=$( system_profiler SPHardwareDataType | grep Serial |  awk '{print $NF}' )
dialogVersion=$( /usr/local/bin/dialog --version )

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Set Dialog path, Command Files, JAMF binary, log files and currently logged-in user
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

jamfBinary="/usr/local/bin/jamf"
dialogBinary="/usr/local/bin/dialog"
promptJSONFile=$( mktemp /var/tmp/promptJSONFile.XXX )
adminCommandFile=$( mktemp /var/tmp/dialogCommandFileAdmin.XXX )
promptCommandFile=$( mktemp /var/tmp/dialogCommandFilePrompt.XXX )

# Set permissions on Dialog Command Files
chmod -v 555 /var/tmp/dialogCommandFile*

osVersion=$( sw_vers -productVersion )
osBuild=$( sw_vers -buildVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
loggedInUserFullname=$( id -F "${loggedInUser}" )
loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print toupper(substr($0,1,1))substr($0,2)}' )

# Create `overlayicon` from Self Service's custom icon (thanks, @meschwartz!)
xxd -p -s 260 "$(defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path)"/Icon$'\r'/..namedfork/rsrc | xxd -r -p > /var/tmp/overlayicon.icns
overlayicon="/var/tmp/overlayicon.icns"

####################################################################################################
#
# Prompt dialog
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# "Prompt" dialog Title, Message and Icon
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

promptDialogTitle="Request To Elevate Access"
promptDialogMessage="Hello ${loggedInUserFirstname}, the following must be filled out before administrative access can be given"

promptJSON='
{
	"commandfile" : "'"${promptCommandFile}"'",
	"title" : "'"${promptDialogTitle}"'",
	"titlefont" : "size=22",
	"message" : "'"${promptDialogMessage}"'",
	"icon" : "'"${icon}"'",
    "infotext" : "'"${scriptVersion}"'",
	"iconsize" : "135",
	"overlayicon" : "'"${overlayicon}"'",
	"moveable" : "true",
    "ontop" : "true",
	"button1text" : "Continue",
    "button2text" : "Cancel",
	"messagealignment" : "left",
	"textfield" : [
		{
			"title" : "Reason for request",
			"required" : true,
			"prompt" : "i.e., I need to install Adobe software"
		},
	],
}
'

####################################################################################################
#
# Admin dialog
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# "Admin" dialog Title, Message and Icon
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

elevationDurationSeconds=$(( ${elevationDurationMinutes} * 60 ))

adminDialogTitle="Admin privileges granted, ${loggedInUserFirstname}"
adminDialogMessage="You have been granted local administrator privileges for ${elevationDurationMinutes} minute(s).  \n\nAfter the timer below expires, your account will return to a standard user."

adminDialogCMD="$dialogBinary -p \
--title \"$adminDialogTitle\" \
--titlefont size=22 \
--message \"$adminDialogMessage\" \
--icon \"$icon\" \
--infotext \"$scriptVersion\" \
--iconsize 135 \
--overlayicon \"$overlayicon\" \
--moveable \
--width 425 \
--height 285 \
--messagefont size=14 \
--messagealignment left \
--position topright \
--timer $elevationDurationSeconds "

####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check if user is already admin, then check if removing admin is required for admin users
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function checkIfAdmin () {

    # Set removeAdminRights to a true or false
    if [[ "${removeAdminRights}" -eq 1 ]] || [[ "${removeAdminRights}" == "true" ]]; then
        removeAdminRights="true"
    else
        removeAdminRights="false"
    fi

    updateScriptLog "${scriptFunctionalName}: Checking to see if ${loggedInUser} is already an admin"
    if /usr/bin/groups $loggedInUser | grep -q -w admin; then
	    updateScriptLog "${scriptFunctionalName}: $loggedInUser is already admin"
	    if [[ "${removeAdminRights}" == "true" ]]; then
		    updateScriptLog "${scriptFunctionalName}: ${loggedInUser} already admin, removeAdminRights set to ${removeAdminRights}, continuing..."
	    else
		    updateScriptLog "${scriptFunctionalName}: removeAdminRights set to ${removeAdminRights}, no need to elevate. Exiting ..."
		    exit 1
	    fi
    else
	    updateScriptLog "${scriptFunctionalName}: $loggedInUser is not an admin user, continuing..."
    fi
}

function captureReason () {
    # Need to write reason to plist
    currentTime=$( date +%Y-%m-%d\ %H:%M:%S )
    elevateReason=$( echo "$currentTime: $elevateReason")
    # Create the ElevationReasons Array in plist
    /usr/libexec/PlistBuddy -c 'add ":ElevationReasons" array' /Library/Preferences/xyz.techitout.elevate.plist 
    # Write the reason to the plist
    /usr/libexec/PlistBuddy -c "add \":ElevationReasons:\" string \"${elevateReason}\"" /Library/Preferences/xyz.techitout.elevate.plist
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse JSON via osascript and JavaScript
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function get_json_value() {
    JSON="$1" osascript -l 'JavaScript' \
        -e 'const env = $.NSProcessInfo.processInfo.environment.objectForKey("JSON").js' \
        -e "JSON.parse(env).$2"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse JSON via osascript and JavaScript for the Prompt dialog (thanks, @bartreardon!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function get_json_value_promptDialog() {
    for var in "${@:2}"; do jsonkey="${jsonkey}['${var}']"; done
    JSON="$1" osascript -l 'JavaScript' \
        -e 'const env = $.NSProcessInfo.processInfo.environment.objectForKey("JSON").js' \
        -e "JSON.parse(env)$jsonkey"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Kill a specified process (thanks, @grahampugh!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function killProcess() {
    process="$1"
    if process_pid=$( pgrep -a "${process}" 2>/dev/null ) ; then
        updateScriptLog "Attempting to terminate the '$process' process …"
        updateScriptLog "(Termination message indicates success.)"
        kill "$process_pid" 2> /dev/null
        if pgrep -a "$process" >/dev/null ; then
            updateScriptLog "ERROR: '$process' could not be terminated."
        fi
    else
        updateScriptLog "The '$process' process isn't running."
    fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Toggle `jamf` binary check-in (thanks, @robjschroeder!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function toggleJamfLaunchDaemon() {
    
    jamflaunchDaemon="/Library/LaunchDaemons/com.jamfsoftware.task.1.plist"

    while [[ ! -f "${jamflaunchDaemon}" ]] ; do
        updateScriptLog "PRE-FLIGHT CHECK: Waiting for installation of ${jamflaunchDaemon}"
        sleep 0.1
    done

    if [[ $(/bin/launchctl list | grep com.jamfsoftware.task.E) ]]; then

        updateScriptLog "${scriptFunctionalName}: Temporarily disable 'jamf' binary check-in"
        /bin/launchctl bootout system "${jamflaunchDaemon}"

    else

        updateScriptLog "QUIT SCRIPT: Re-enabling 'jamf' binary check-in"
        updateScriptLog "QUIT SCRIPT: 'jamf' binary check-in daemon not loaded, attempting to bootstrap and start"
        result="0"

        until [ $result -eq 3 ]; do

            /bin/launchctl bootstrap system "${jamflaunchDaemon}" && /bin/launchctl start "${jamflaunchDaemon}"
            result="$?"

            if [ $result = 3 ]; then
                updateScriptLog "QUIT SCRIPT: Staring 'jamf' binary check-in daemon"
            else
                updateScriptLog "QUIT SCRIPT: Failed to start 'jamf' binary check-in daemon"
            fi

        done

    fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Quit Script (thanks, @bartreadon!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function quitScript() {

    updateScriptLog "QUIT SCRIPT: Exiting …"

    # Stop `caffeinate` process
    updateScriptLog "QUIT SCRIPT: De-caffeinate …"
    killProcess "caffeinate"

    # Remove overlayicon
    if [[ -e ${overlayicon} ]]; then
        updateScriptLog "QUIT SCRIPT: Removing ${overlayicon} …"
        rm "${overlayicon}"
    fi
    
    # Remove promptCommandFile
    if [[ -e ${promptCommandFile} ]]; then
        updateScriptLog "QUIT SCRIPT: Removing ${promptCommandFile} …"
        rm "${promptCommandFile}"
    fi

    # Remove promptJSONFile
    if [[ -e ${promptJSONFile} ]]; then
        updateScriptLog "QUIT SCRIPT: Removing ${promptJSONFile} …"
        rm "${promptJSONFile}"
    fi

    # Remove adminCommandFile
    if [[ -e ${adminCommandFile} ]]; then
        updateScriptLog "QUIT SCRIPT: Removing ${adminCommandFile} …"
        rm "${adminCommandFile}"
    fi

    # Delete the LaunchDaemon plist
    updateScriptLog "QUIT SCRIPT: Removing LaunchDaemon plist"
    /bin/rm "/Library/LaunchDaemons/${plistDomain}.elevate.plist"

    # Kill the LaunchDaemon process
    updateScriptLog "QUIT SCRIPT: Killing LaunchDaemon process"
    /bin/launchctl remove ${plistDomain}.elevate

    # Remove Dialog command files
    updateScriptLog "QUIT SCRIPT: Removing Dialog script"
    rm /var/tmp/dialog*

    # Remove overlayicon
    updateScriptLog "QUIT SCRIPT: Removing Dialog overlayicon"
    rm /var/tmp/overlay.icns

    # Remove Script
    updateScriptLog "QUIT SCRIPT: Removing Elevate script"
    rm /var/tmp/elevate.*

    # Re-enable the Jamf Binary Check-In process
    toggleJamfLaunchDaemon

    # Send Jamf Pro an inventory update
    updateScriptLog "QUIT SCRIPT: Submitting Jamf Inventory Update"
    /usr/local/bin/jamf recon

    # Execute a Jamf Pro policy trigger (Parameter 6)
    /usr/local/bin/jamf policy -event ${jamfProPolicyCustomEvent}

    # Done
    updateScriptLog "QUIT SCRIPT: Completed"

	updateScriptLog "QUIT SCRIPT: Exiting with exit code ${exitCode}"
	exit "${exitCode}"

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Webhook Message (Microsoft Teams or Slack) (thanks, @robjschroeder! and @iDrewbs!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function webHookMessage() {

    # # Jamf Pro URL for on-prem, multi-node, clustered environments
    # case ${jamfProURL} in
    #     *"beta"*    ) jamfProURL="https://jamfpro-beta.internal.company.com/" ;;
    #     *           ) jamfProURL="https://jamfpro-prod.internal.company.com/" ;;
    # esac
    # Run initial recon
    reconRaw=$( eval "${jamfBinary} recon -verbose | tee -a ${scriptLog}" )
    computerID=$( echo "${reconRaw}" | grep '<computer_id>' | xmllint --xpath xmllint --xpath '/computer_id/text()' - )

    jamfProURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
    jamfProComputerURL="${jamfProURL}computers.html?id=${computerID}&o=r"

    if [[ $webhookURL == *"slack"* ]]; then
        
        updateScriptLog "Generating Slack Message …"
        
        webHookdata=$(cat <<EOF
        {
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": "Security: Elevate Request",
                        "emoji": true
                    }
                },
                {
                    "type": "section",
                    "fields": [
                        {
                            "type": "mrkdwn",
                            "text": "*Elevation Request:*\n$( scutil --get ComputerName )"
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*Serial:*\n${serialNumber}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*User:*\n${loggedInUser}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*OS Version:*\n${osVersion}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*Reason:*\n${elevateReason}"
                        }
                    ]
                },
                {
                    "type": "actions",
                    "elements": [
                        {
                            "type": "button",
                            "text": {
                                "type": "plain_text",
                                "text": "View in Jamf Pro"
                                },
                            "style": "primary",
                            "url": "${jamfProComputerURL}"
                        }
                    ]
                }
            ]
        }
EOF
)

        # Send the message to Slack
        updateScriptLog "Send the message to Slack …"
        updateScriptLog "${webHookdata}"
        
        # Submit the data to Slack
        /usr/bin/curl -sSX POST -H 'Content-type: application/json' --data "${webHookdata}" $webhookURL 2>&1
        
        webhookResult="$?"
        updateScriptLog "Slack Webhook Result: ${webhookResult}"
        
    else
        
        updateScriptLog "Generating Microsoft Teams Message …"

        # URL to an image to add to your notification
        activityImage="https://creazilla-store.fra1.digitaloceanspaces.com/cliparts/78010/old-mac-computer-clipart-md.png"

        webHookdata=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "E4002B",
    "summary": "Security: Elevate Request",
    "sections": [{
        "activityTitle": "Security: Elevate Request",
        "activitySubtitle": "${jamfProURL}",
        "activityImage": "${activityImage}",
        "facts": [{
            "name": "Mac Serial",
            "value": "${serialNumber}"
        }, {
            "name": "Computer Name",
            "value": "$( scutil --get ComputerName )"
        }, {
            "name": "User",
            "value": "${loggedInUser}"
        }, {
            "name": "Operating System Version",
            "value": "${osVersion}"
        }, {
            "name": "Reason",
            "value": "${elevateReason}"
}],
        "markdown": true,
        "potentialAction": [{
        "@type": "OpenUri",
        "name": "View in Jamf Pro",
        "targets": [{
        "os": "default",
            "uri": "${jamfProComputerURL}"
            }]
        }]
    }]
}
EOF
)

    # Send the message to Microsoft Teams
    updateScriptLog "Send the message Microsoft Teams …"

    curl --request POST \
    --url "${webhookURL}" \
    --header 'Content-Type: application/json' \
    --data "${webHookdata}"
    
    webhookResult="$?"
    updateScriptLog "Microsoft Teams Webhook Result: ${webhookResult}"

    updateScriptLog "${scriptFunctionalName}: Removing webHookURL from PLIST"
    /usr/libexec/PlistBuddy -c "Delete :webhookURL" /Library/Preferences/xyz.techitout.elevate.plist

    
    fi
    
}

####################################################################################################
#
# Program
#
####################################################################################################

# Check if the user is admin and if removeAdminRights is false then quit
checkIfAdmin

# Display prompt dialog
echo $promptJSON > $promptJSONFile
promptResults=$( eval "$dialogBinary --jsonfile ${promptJSONFile} --json" | sed 's/ERROR: Unable to delete command file//g' )

# Evaluate User Input
if [[ -z "${promptResults}" ]]; then
    promptReturnCode="2"
else
    promptReturnCode="0"
fi

case "${promptReturnCode}" in
    0) # Process exit code 0 scenario here
    elevateReason=$(get_json_value_promptDialog "${promptResults}" "Reason for request")
    updateScriptLog "${scriptFunctionalName}: ${loggedInUser} provided input"
    updateScriptLog "${scriptFunctionalName}: Reason for elevation: ${elevateReason}"
    updateScriptLog "${scriptFunctinoalName}: Continuing to elevate ${loggedInUser}"
    ;;
    2) # Process exit code 1 scenario here
    updateScriptLog "${scriptFunctionalName}: ${loggedInUser} clicked cancel, exiting..."
    exitCode="1"
    quitScript
    ;;
    *) # Process Catch All scenario
    updateScriptLog "${scriptFunctionalName}: Something else happened, exiting..."
    exitCode="2"
    quitScript
    ;;
esac

# Disable the jamf binary check-in process
toggleJamfLaunchDaemon

captureReason

# Promote the user to admin
updateScriptLog "${scriptFunctionalName}: Promoting ${loggedInUser} to admin"
/usr/sbin/dseditgroup -o edit -a $loggedInUser -t user admin

# Confirm loggedInUser's group membership
updateScriptLog "${scriptFunctionalName}: Confirming ${loggedInUser}'s group membership in '80(admin)' …"
/usr/bin/id $loggedInUser | grep 80 | tee -a ${scriptLog}
updateScriptLog ""

# Launching admin dialog
updateScriptLog "${scriptFunctionalName}: Launching user dialog for ${elevationDurationSeconds} seconds …"
updateScriptLog ""
results=$(eval "$adminDialogCMD" & webHookMessage)
echo $results 

# Demote the user to standard
updateScriptLog "${scriptFunctionalName}: Allowed time of ${elevationDurationSeconds} seconds has passed, demoting ${loggedInUser} to standard"
/usr/sbin/dseditgroup -o edit -d $loggedInUser -t user admin

sleep 5

# Confirm loggedInUser's group membership
updateScriptLog "Elevate: Confirming ${loggedInUser} is NOT a member of '80(admin)' …"
updateScriptLog "(No results equals sucessful removal from '80(admin)' group.)"
/usr/bin/id $loggedInUser | grep 80 | tee -a ${scriptLog}

# Collect logs
timestamp=$(date +%s)
/usr/bin/log collect --output /private/var/log/elevateLog-$timestamp.logarchive --last "${elevationDurationMinutes}"m

quitScript

==endOfScript==

if [ $? = 0 ]; then
	echo "Creating script at \"/var/tmp/elevate.sh\""
else
	echo "Failed creating script at \"/var/tmp/elevate.sh\""
fi

# set correct ownership and permissions on run-startosinstall.zsh script

/usr/sbin/chown root:wheel "/var/tmp/elevate.sh" && /bin/chmod +x "/var/tmp/elevate.sh"

if [ $? = 0 ]; then
	echo "Setting correct ownership and permissions on \"/var/tmp/elevate.sh\" script"
else
	echo "Failed setting correct ownership and permissions on\"/var/tmp/elevate.sh\" script"
fi

# Set up the LaunchDaemon
tee /Library/LaunchDaemons/"${plistDomain}".elevate.plist &>/dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
	</dict>
	<key>Label</key>
	<string>${plistDomain}.elevate</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/zsh</string>
		<string>-c</string>
		<string>"/var/tmp/elevate.sh"</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

# shellcheck disable=SC2181
if [ $? = 0 ]; then
	echo "Creating LaunchDaemon at /Library/LaunchDaemons/${plistDomain}.elevate.plist"
else
	echo "Failed creating LaunchDaemon at /Library/LaunchDaemons/${plistDomain}.elevate.plist"
fi

# set correct ownership and permissions on LaunchDaemon

/usr/sbin/chown root:wheel /Library/LaunchDaemons/"${plistDomain}".elevate.plist && /bin/chmod 644 /Library/LaunchDaemons/"${plistDomain}".elevate.plist

# report to policy whether ownership and permissions were set
# shellcheck disable=SC2181

if [ $? = 0 ]; then
	echo "Setting correct ownership and permissions on LaunchDaemon"
else
	echo "Failed setting correct ownership and permissions on LaunchDaemon"
fi

# start LaunchDaemon after installation

/bin/launchctl bootstrap system /Library/LaunchDaemons/"${plistDomain}".elevate.plist && /bin/launchctl start /Library/LaunchDaemons/"${plistDomain}".elevate.plist

# report to policy whether LaunchDaemon was started

if [ $? = 3 ]; then
	echo "Starting LaunchDaemon"
else
	echo "Failed starting LaunchDaemon"
fi

exit 0