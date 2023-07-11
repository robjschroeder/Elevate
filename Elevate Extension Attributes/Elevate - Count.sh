#!/bin/bash

# Created 07.11.2023 @robjschroeder
# This script is to be used as an extension attribute in Jamf Pro. 

# Gathers the number of elements in the Elevation Reasons array in the 
# Elevate Plist, this will give a count of how many
# times a user has elevated their account.

# Data Type = Integer
# Input Type = Script

# Extension Attribute to grab reasons for priv elevation
plistBuddy="/usr/libexec/PlistBuddy -c"
elevatePlist="/Library/Preferences/xyz.techitout.elevate.plist"
key="ElevationReasons"

i=0
while true ; do
	$plistBuddy "Print :$key:$i" "$elevatePlist" >/dev/null 2>/dev/null
	if [ $? -ne 0 ]; then
		break
	fi
	i=$(($i + 1))
done

echo "<result>$i</result>"
