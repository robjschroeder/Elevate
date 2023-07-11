# Elevate
Elevate is a script that can be ran from Jamf Pro to help elevate a standard user to admin for a specific amount of time

![GitHub release (latest by date)](https://img.shields.io/github/v/release/robjschroeder/Elevate?display_name=tag)

This script is meant to be ran as a Self Service with Jamf Pro. The script will promote the currently logged in user to an Admin user for a defined number of seconds, then demote the user back to a standard account while providing dialog to the end-user. The script uses swiftDialog to present the dialog to the user: [https://github.com/bartreardon/swiftDialog](https://github.com/bartreardon/swiftDialog)
<img width="932" alt="Screenshot 2023-07-11 at 3 45 21 PM" src="https://github.com/robjschroeder/Elevate/assets/23343243/f7bcb268-dea9-49ce-928f-278db7a96644">

<img width="493" alt="Screenshot 2023-04-22 at 11 10 20 PM" src="https://user-images.githubusercontent.com/23343243/233823115-7266230a-2411-4c9e-be4b-a1bc6d1fbdb6.png">

## New Features
### Managed Configuration Profile
With version 2.0.0, I have added the ability to apply a configuration profile at the MDM level to Elevate. This is not required, but for me makes things easier to manage at the organizational level. There is a JSON manifest that can be uploaded to Jamf Pro for help in building the configuraiton profile. 
#### Note on managed configuration profile
If you apply the managed configuration profile, all parameters passed into the script will be ignored. The script looks for the profile located at /Library/Managed Preferences/xyz.techitout.elevate.plist and will ignore the params passed in from a Jamf Pro policy. This is the ensure that the settings applied at the MDM level are respected. 
### Capture the reason a user is using Elevate
With version 2.0.0 I have added an additional prompt that will ask the user to provide a reason they need their rights elevated. This reason is captured in /Library/Preferences/xyz.techitout.elevate.plist with a timestamp. This will help to ensure that requests are being used for legitimate reasons and can be audited at any point. 
### Use webhooks to be notified of Elevation requests
With 2.0.0 you can configure a Teams or Slack webhook URL to send the Elevation request to. This can be handy to get a feel for what your users are requesting admin for and how often. 

## Why build this
In my environment, I needed a way to be able to temporarily give admin access to certain users while having the confidence that they would return to a standard user after the given amount of time has passed. Also, I would like to swiftDialog-ize everything!

## How to use
1. Add the Elevate.sh script into your Jamf Pro
2. Create a new policy in Jamf Pro, scoped to computers that would need this script to be ran
3. Make sure to have the script available in Self Service to the end-user
4. (Optional) Upload the JSON manifest for your Elevate configuration profile and apply to the computers that get access to Elevate

If the target computer doesn't have swiftDialog, the script will curl the latest version and install it before continuing. 

Always test in your own environment before pushing to production.
