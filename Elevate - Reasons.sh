#!/bin/bash

# Created 07.11.2023 @robjschroeder
# This script is to be used as an extension attribute in Jamf Pro. 

# Gathers the elements in the Elevation Reasons array in the 
# Elevate Plist and echos those reasons out for the EA.

# Data Type = String
# Input Type = Script

# Extension Attribute to grab reasons for priv elevation
plistBuddy="/usr/libexec/PlistBuddy -c"
elevatePlist="/Library/Preferences/xyz.techitout.elevate.plist"
key="ElevationReasons"

#list=$( $plistBuddy "Print \":ElevationReasons:\" $elevatePlist")
list=$( $plistBuddy "Print :$key" $elevatePlist)

items=`awk -F" = " '
{
		if ($0 ~ /[{}]/){}
		else{printf $1","}
}' <<< "${list}"`
			
IFS=',' read -ra array <<< "$items"
			
for element in "${array[@]}"; do
	elementArray+=($(echo "$element \ "))
done
			
echo "<result>${elementArray[@]}</result>"
