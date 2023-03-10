#!/bin/bash

# Script to promote the logged in user to admin then demote 
# back to standard user after a defined number of seconds
#
# Created 02.23.2023 @robjschroeder
# Updated 03.10.2023 @robjschroeder

##################################################
# Remove old artifacts, if any ...
# Remove Elevate script
if [[ -f /var/tmp/elevate.sh ]]; then
	rm -rf /var/tmp/elevate.sh
fi

# Delete the launch daemon plist
if [[ -f /Library/LaunchDaemons/xyz.techitout.elevate.plist ]]; then
	/bin/rm "/Library/LaunchDaemons/xyz.techitout.elevate.plist"
fi

# Kill the launch daemon process
/bin/launchctl remove xyz.techitout.elevate

##################################################
# Create the elevate script in /var/tmp/

/usr/bin/tee /var/tmp/elevate.sh<<"EOF"
#!/bin/bash
set -x

# Script Version, OS attributes, Logged in User, and time to promote
scriptVersion="1.0.1"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin/
scriptLog="/private/var/tmp/xyz.techitout.elevate.log"
osVersion=$( sw_vers -productVersion )
osBuild=$( sw_vers -buildVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

##################################################
# Time to Elevate to admin in seconds
seconds="600"
##################################################

# Client-side logging
if [[ ! -f "${scriptLog}" ]]; then
	touch "${scriptLog}"
fi

# Client-side Script Logging Function (Thanks @dan-snelson!!)
function updateScriptLog() {
	echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

updateScriptLog "\n###\n# Elevate (${scriptVersion})\n# https://techitout.xyz/\n###\n"
updateScriptLog "Pre-flight Check: Initiating ..."

# Confirm script is running as root

if [[ $(id -u) -ne 0 ]]; then
	updateScriptLog "Pre-flight Check: This script must be run as root; exiting."
	exit 1
fi

# Validate Operating System Version and Build
# Since swiftDialog requires at least macOS 11 Big Sur, first confirm the major OS version
# shellcheck disable=SC2086 # purposely use single quotes with osascript

if [[ "${osMajorVersion}" -ge 11 ]] ; then
	
	updateScriptLog "Pre-flight Check: macOS ${osMajorVersion} installed; checking build version ..."
	
# The Mac is running an operating system older than macOS 11 Big Sur; exit with error
else
	
	updateScriptLog "Pre-flight Check: swiftDialog requires at least macOS 11 Big Sur and this Mac is running ${osVersion} (${osBuild}), exiting with error."
	osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\rExpected macOS Build Big Sur (or newer), but found macOS '${osVersion}' ('${osBuild}').\r\r" with title "Elevate: Detected Outdated Operating System" buttons {"Open Software Update"} with icon caution'
	exit 1
	
fi

# Ensure computer does not go to sleep while running this script (thanks, @grahampugh!)

updateScriptLog "Pre-flight Check: Caffeinating this script (PID: $$)"
caffeinate -dimsu -w $$ &

# Confirm Dock is running / user is at Desktop

until pgrep -q -x "Finder" && pgrep -q -x "Dock"; do
	updateScriptLog "Pre-flight Check: Finder & Dock are NOT running; pausing for 1 second"
	sleep 1
done

updateScriptLog "Pre-flight Check: Finder & Dock are running; proceeding …"

# Validate logged-in user

loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

if [[ -z "${loggedInUser}" || "${loggedInUser}" == "loginwindow" ]]; then
	updateScriptLog "Pre-flight Check: No user logged-in; exiting."
	exit 1
else
	loggedInUserFullname=$( id -F "${loggedInUser}" )
	loggedInUserFirstname=$( echo "$loggedInUserFullname" | cut -d " " -f 1 )
	loggedInUserID=$(id -u "${loggedInUser}")
fi

# Check for / install swiftDialog (Thanks big bunches, @acodega!)

function dialogCheck() {
	
	# Output Line Number in `verbose` Debug Mode
	if [[ "${debugMode}" == "verbose" ]]; then updateScriptLog "Pre-flight Check: # # # SETUP YOUR MAC VERBOSE DEBUG MODE: Line No. ${LINENO} # # #" ; fi
	
	# Get the URL of the latest PKG From the Dialog GitHub repo
	dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	
	# Expected Team ID of the downloaded PKG
	expectedDialogTeamID="PWA5E9TQ59"
	
	# Check for Dialog and install if not found
	if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
		
		updateScriptLog "Pre-flight Check: Dialog not found. Installing..."
		
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
			updateScriptLog "Pre-flight Check: swiftDialog version ${dialogVersion} installed; proceeding..."
			
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
		
		updateScriptLog "Pre-flight Check: swiftDialog version $(dialog --version) found; proceeding..."
		
	fi
	
}

if [[ ! -e "/Library/Application Support/Dialog/Dialog.app" ]]; then
	dialogCheck
fi

# Pre-flight Checks Complete

updateScriptLog "Pre-flight Check: Complete"

# Dialog Variables

# infobox-related variables
macOSproductVersion="$( sw_vers -productVersion )"
macOSbuildVersion="$( sw_vers -buildVersion )"
serialNumber=$( system_profiler SPHardwareDataType | grep Serial |  awk '{print $NF}' )
dialogVersion=$( /usr/local/bin/dialog --version )

# Convert seconds to minutes
minutes=$(($seconds/60))

# Set Dialog path, Command Files, JAMF binary, log files and currently logged-in user

dialogApp="/Library/Application\ Support/Dialog/Dialog.app/Contents/MacOS/Dialog"
dialogBinary="/usr/local/bin/dialog"
dialogCommandFile=$( mktemp /var/tmp/dialog.XXX )

# Dialog
dialogTitle="Admin privileges granted, ${loggedInUserFirstname}"
dialogMessage="You have been granted local administrator privileges on your Mac. After $minutes minute(s), your account will return to a standard user. Thank you!"
dialogBannerImage="https://i.pinimg.com/564x/95/32/9e/95329efbadbe3fdaf67bf2df6add6fe4.jpg"
dialogBannerText="Admin privileges granted, ${loggedInUserFirstname}"

# Welcome icon set to either light or dark, based on user's Apperance setting (thanks, @mm2270!)
appleInterfaceStyle=$( /usr/bin/defaults read /Users/"${loggedInUser}"/Library/Preferences/.GlobalPreferences.plist AppleInterfaceStyle 2>&1 )
if [[ "${appleInterfaceStyle}" == "Dark" ]]; then
	welcomeIcon="/Users/$loggedInUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
else
	welcomeIcon="/Users/$loggedInUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
fi

dialogCMD="$dialogBinary -p \
--title \"$dialogTitle\" \
--message \"$dialogMessage\" \
--icon \"$welcomeIcon\" \
--moveable \
--width 400 \
--height 350 \
--messagefont size=15 \
--messagealignment centre \
--position topright \
--timer \"$seconds\" "

# Promote the user to admin
updateScriptLog "Elevate: Promoting ${loggedInUser} to admin"
/usr/sbin/dseditgroup -o edit -a $loggedInUser -t user admin

results=$(eval "$dialogCMD")
echo $results

# Demote the user to standard
updateScriptLog "Elevate: Allowed time has passed, demoting ${loggedInUser} to standard"
/usr/sbin/dseditgroup -o edit -d $loggedInUser -t user admin

sleep 5

# Delete the launch daemon plist
updateScriptLog "Elevate: Removing launch daemon plist"
/bin/rm "/Library/LaunchDaemons/xyz.techitout.elevate.plist"

# Kill the launch daemon process
updateScriptLog "Elevate: Killing launch daemon process"
/bin/launchctl remove xyz.techitout.elevate

# Remove Script
updateScriptLog "Elevate: Removing Elevate script"
rm /var/tmp/elevate.sh

# Send Jamf Pro an inventory update
updateScriptLog "Elevate: Submitting Jamf Inventory Update"
/usr/local/bin/jamf recon

exit 0
EOF

# report to policy whether script was created

if [ $? = 0 ]; then
	echo "Creating script at \"/var/tmp/elevate.sh\""
else
	echo "Failed creating script at \"/var/tmp/elevate.sh\""
fi

# set correct ownership and permissions on run-startosinstall.zsh script

/usr/sbin/chown root:wheel "/var/tmp/elevate.sh" && /bin/chmod +x "/var/tmp/elevate.sh"

# report to policy whether ownership and permissions were set

if [ $? = 0 ]; then
	echo "Setting correct ownership and permissions on \"/var/tmp/elevate.sh\" script"
else
	echo "Failed setting correct ownership and permissions on\"/var/tmp/elevate.sh\" script"
fi

# Set up the LaunchDaemon
tee /Library/LaunchDaemons/xyz.techitout.elevate.plist << EOF
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
	<string>xyz.techitout.elevate</string>
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

if [ $? = 0 ]; then
	echo "Creating launch daemon at /Library/LaunchDaemons/xyz.techitout.elevate.plist"
else
	echo "Failed creating launch daemon at /Library/LaunchDaemons/xyz.techitout.elevate.plist"
fi

# set correct ownership and permissions on launch daemon

/usr/sbin/chown root:wheel /Library/LaunchDaemons/xyz.techitout.elevate.plist && /bin/chmod 644 /Library/LaunchDaemons/xyz.techitout.elevate.plist

# report to policy whether ownership and permissions were set

if [ $? = 0 ]; then
	echo "Setting correct ownership and permissions on launch daemon"
else
	echo "Failed setting correct ownership and permissions on launch daemon"
fi

# start launch daemon after installation

/bin/launchctl bootstrap system /Library/LaunchDaemons/xyz.techitout.elevate.plist && /bin/launchctl start /Library/LaunchDaemons/xyz.techitout.elevate.plist

# report to policy whether launch daemon was started

if [ $? = 3 ]; then
	echo "Starting launch daemon"
else
	echo "Failed starting launch daemon"
fi

exit 0
