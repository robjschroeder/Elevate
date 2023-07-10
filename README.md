# Elevate
Elevate is a script that can be ran from Jamf Pro to help elevate a standard user to admin for a specific amount of time

![GitHub release (latest by date)](https://img.shields.io/github/v/release/robjschroeder/Elevate?display_name=tag)

This script is meant to be ran as a Self Service with Jamf Pro. The script will promote the currently logged in user to an Admin user for a defined number of seconds, then demote the user back to a standard account while providing dialog to the end-user. The script uses swiftDialog to present the dialog to the user: [https://github.com/bartreardon/swiftDialog](https://github.com/bartreardon/swiftDialog)
<img width="493" alt="Screenshot 2023-04-22 at 11 10 20 PM" src="https://user-images.githubusercontent.com/23343243/233823115-7266230a-2411-4c9e-be4b-a1bc6d1fbdb6.png">



## Why build this
In my environment, I needed a way to be able to temporarily give admin access to certain users while having the confidence that they would return to a standard user after the given amount of time has passed. Also, I would like to swiftDialog-ize everything!

## How to use
1. Add the Elevate.sh script into your Jamf Pro
2. Create a new policy in Jamf Pro, scoped to computers that would need this script to be ran
3. Make sure to have the script available in Self Service to the end-user

If the target computer doesn't have swiftDialog, the script will curl the latest version and install it before continuing. 

Always test in your own environment before pushing to production. Current development version: 2.0.0-b1
