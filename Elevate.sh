#!/bin/bash

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
# - Added line to collect log archive for activity duration. Log will be created at /var/log/elevateLog-${timestamp}.logarchive
#
##################################################
# Variables

# Script Version
scriptVersion="1.0.4"

# Parameter 4: Reverse Domain Name Notation (i.e., "xyz.techitout")
plistDomain="${4:-"com.company"}"

# Parameter 5: Elevation Duration (in minutes)
elevationDurationMinutes="${5:-"1"}"
elevationDurationSeconds=$(( elevationDurationMinutes * 60 ))

# Script Log Location (based on $plistDomain)
scriptLog="/private/var/log/${plistDomain}.log"



##################################################
# Remove old artifacts, if any ...
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

##################################################
# Create `overlayicon` from Self Service's custom icon (thanks, Mike Schwartz!)
xxd -p -s 260 "$(defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path)"/Icon$'\r'/..namedfork/rsrc | xxd -r -p > /var/tmp/overlay.icns

##################################################
# Create the elevate script in /var/tmp/

/usr/bin/tee /var/tmp/elevate.sh<<"EOF"
#!/bin/bash
#set -x

# Script Version, OS attributes, Logged in User, and time to promote
scriptVersion="placeholderScriptVersion"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin/
scriptLog="placeholderScriptLog"
osVersion=$( sw_vers -productVersion )
osBuild=$( sw_vers -buildVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

# Client-side logging
if [[ ! -f "${scriptLog}" ]]; then
	touch "${scriptLog}"
fi

# Client-side Script Logging Function (Thanks @dan-snelson!!)
function updateScriptLog() {
	echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

updateScriptLog "\n###\n# Elevate (placeholderScriptVersion)\n# https://techitout.xyz/\n###\n"
updateScriptLog "Elevate Pre-flight: Initiating ..."

# Confirm script is running as root

if [[ $(id -u) -ne 0 ]]; then
	updateScriptLog "Elevate Pre-flight: This script must be run as root; exiting."
	exit 1
fi

# Validate Operating System Version and Build
# Since swiftDialog requires at least macOS 11 Big Sur, first confirm the major OS version
# shellcheck disable=SC2086 # purposely use single quotes with osascript

if [[ "${osMajorVersion}" -ge 11 ]] ; then
	
	updateScriptLog "Elevate Pre-flight: macOS ${osMajorVersion} installed; checking build version ..."
	
# The Mac is running an operating system older than macOS 11 Big Sur; exit with error
else
	
	updateScriptLog "Elevate Pre-flight: swiftDialog requires at least macOS 11 Big Sur and this Mac is running ${osVersion} (${osBuild}), exiting with error."
	osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\rExpected macOS Build Big Sur (or newer), but found macOS '${osVersion}' ('${osBuild}').\r\r" with title "Elevate: Detected Outdated Operating System" buttons {"Open Software Update"} with icon caution'
	/usr/bin/open /System/Library/CoreServices/Software\ Update.app
	exit 1
	
fi

# Ensure computer does not go to sleep while running this script (thanks, @grahampugh!)

updateScriptLog "Elevate Pre-flight: Caffeinating this script (PID: $$)"
caffeinate -dimsu -w $$ &

# Confirm Dock is running / user is at Desktop

until pgrep -q -x "Finder" && pgrep -q -x "Dock"; do
	updateScriptLog "Elevate Pre-flight: Finder & Dock are NOT running; pausing for 1 second"
	sleep 1
done

updateScriptLog "Elevate Pre-flight: Finder & Dock are running; proceeding …"

# Validate logged-in user

loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

if [[ -z "${loggedInUser}" || "${loggedInUser}" == "loginwindow" ]]; then
	updateScriptLog "Elevate Pre-flight: No user logged-in; exiting."
	exit 1
else
	loggedInUserFullname=$( id -F "${loggedInUser}" )
	loggedInUserFirstname=$( echo "$loggedInUserFullname" | cut -d " " -f 1 )
	loggedInUserID=$(id -u "${loggedInUser}")
fi

# Check for / install swiftDialog (Thanks big bunches, @acodega!)

function dialogCheck() {
	
	# Get the URL of the latest PKG From the Dialog GitHub repo
	dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	
	# Expected Team ID of the downloaded PKG
	expectedDialogTeamID="PWA5E9TQ59"
	
	# Check for Dialog and install if not found
	if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
		
		updateScriptLog "Elevate Pre-flight: Dialog not found. Installing..."
		
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
			updateScriptLog "Elevate Pre-flight: swiftDialog version ${dialogVersion} installed; proceeding..."
			
		else
			
			# Display a so-called "simple" dialog if Team ID fails to validate
			osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "Setup Your Mac: Error" buttons {"Close"} with icon caution'
			completionActionOption="Quit"
			exitCode="1"
			quitScript
			
		fi
		
		# Remove the temporary working directory when done
		/bin/rm -Rf "$tempDirectory"
		
	else
		
		updateScriptLog "Elevate Pre-flight: swiftDialog version $(dialog --version) found; proceeding..."
		
	fi
	
}

if [[ ! -e "/Library/Application Support/Dialog/Dialog.app" ]]; then
	dialogCheck
fi

# Elevate Pre-flights Complete

updateScriptLog "Elevate Pre-flight: Complete"

# Dialog Variables

# infobox-related variables
macOSproductVersion="$( sw_vers -productVersion )"
macOSbuildVersion="$( sw_vers -buildVersion )"
serialNumber=$( system_profiler SPHardwareDataType | grep Serial |  awk '{print $NF}' )
dialogVersion=$( /usr/local/bin/dialog --version )

# Set Dialog path, Command Files, JAMF binary, log files and currently logged-in user

dialogApp="/Library/Application\ Support/Dialog/Dialog.app/Contents/MacOS/Dialog"
dialogBinary="/usr/local/bin/dialog"
dialogCommandFile=$( mktemp /var/tmp/dialog.XXX )

# Dialog
dialogTitle="Admin privileges granted, ${loggedInUserFirstname}"
dialogMessage="You have been granted local administrator privileges for placeholderElevationDurationMinutes minute(s).  \n\nAfter the timer below expires, your account will return to a standard user."
dialogBannerImage="https://i.pinimg.com/564x/95/32/9e/95329efbadbe3fdaf67bf2df6add6fe4.jpg"
dialogBannerText="Admin privileges granted, ${loggedInUserFirstname}"

dialogCMD="$dialogBinary -p \
--title \"$dialogTitle\" \
--titlefont size=22 \
--message \"$dialogMessage\" \
--icon /System/Library/CoreServices/KeyboardSetupAssistant.app/Contents/Resources/AppIcon.icns \
--iconsize 135 \
--overlayicon /var/tmp/overlay.icns \
--moveable \
--width 425 \
--height 285 \
--messagefont size=14 \
--messagealignment left \
--position topright \
--timer placeholderElevationDurationSeconds "

# Promote the user to admin
updateScriptLog "Elevate: Promoting ${loggedInUser} to admin"
/usr/sbin/dseditgroup -o edit -a $loggedInUser -t user admin

# Confirm loggedInUser's group membership
updateScriptLog "Elevate: Confirming ${loggedInUser}'s group membership in '80(admin)' …"
/usr/bin/id $loggedInUser | grep 80 | tee -a placeholderScriptLog
updateScriptLog ""

# Launching user dialog
updateScriptLog "Elevate: Launching user dialog for placeholderElevationDurationSeconds seconds …"
updateScriptLog ""
results=$(eval "$dialogCMD")
echo $results

# Demote the user to standard
updateScriptLog "Elevate: Allowed time of placeholderElevationDurationSeconds seconds has passed, demoting ${loggedInUser} to standard"
/usr/sbin/dseditgroup -o edit -d $loggedInUser -t user admin

sleep 5

# Confirm loggedInUser's group membership
updateScriptLog "Elevate: Confirming ${loggedInUser} is NOT a member of '80(admin)' …"
updateScriptLog "(No results equals sucessful removal from '80(admin)' group.)"
/usr/bin/id $loggedInUser | grep 80 | tee -a placeholderScriptLog

# Collect logs
timestamp=$(date +%s)
/usr/bin/log collect --output /var/log/elevateLog-$timestamp.logarchive --last "placeholderElevationDurationMinutes"m

# Delete the LaunchDaemon plist
updateScriptLog "Elevate: Removing LaunchDaemon plist"
/bin/rm "/Library/LaunchDaemons/${plistDomain}.elevate.plist"

# Kill the LaunchDaemon process
updateScriptLog "Elevate: Killing LaunchDaemon process"
/bin/launchctl remove ${plistDomain}.elevate

# Remove Dialog command files
updateScriptLog "Elevate: Removing Dialog script"
rm /var/tmp/dialog*

# Remove overlayicon
updateScriptLog "Elevate: Removing Dialog overlayicon"
rm /var/tmp/overlay.icns

# Remove Script
updateScriptLog "Elevate: Removing Elevate script"
rm /var/tmp/elevate.*

# Send Jamf Pro an inventory update
updateScriptLog "Elevate: Submitting Jamf Inventory Update"
/usr/local/bin/jamf recon

# Done
updateScriptLog "Elevate: Completed"

exit 0
EOF

# report to policy whether script was created
# shellcheck disable=SC2181
if [ $? = 0 ]; then
	echo "Creating script at \"/var/tmp/elevate.sh\""
else
	echo "Failed creating script at \"/var/tmp/elevate.sh\""
fi

# Update placeholders with variable values

/usr/bin/sed -i.backup1 "s|placeholderScriptVersion|${scriptVersion}|g" /var/tmp/elevate.sh
/usr/bin/sed -i.backup2 "s|placeholderScriptLog|${scriptLog}|g" /var/tmp/elevate.sh
/usr/bin/sed -i.backup3 "s|placeholderElevationDurationSeconds|${elevationDurationSeconds}|g" /var/tmp/elevate.sh
/usr/bin/sed -i.backup4 "s|placeholderElevationDurationMinutes|${elevationDurationMinutes}|g" /var/tmp/elevate.sh

# set correct ownership and permissions on run-startosinstall.zsh script

/usr/sbin/chown root:wheel "/var/tmp/elevate.sh" && /bin/chmod +x "/var/tmp/elevate.sh"

# report to policy whether ownership and permissions were set
# shellcheck disable=SC2181

if [ $? = 0 ]; then
	echo "Setting correct ownership and permissions on \"/var/tmp/elevate.sh\" script"
else
	echo "Failed setting correct ownership and permissions on\"/var/tmp/elevate.sh\" script"
fi

# Set up the LaunchDaemon
tee /Library/LaunchDaemons/"${plistDomain}".elevate.plist << EOF
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
