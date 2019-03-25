# MacADUK-2019
## MDM: Improve your automated MDM enrollments

Imaging is a dirty word! Here are resources from my part of this presentation at MacADUK (26th March 2019, Prospero House, London). I was honoured to share the stage with the one and only Joel Rennich, director of Jamf Connect, at Jamf. My focus centred around leveraging new functionality in NoMAD Login AD to help automate MDM based provisioning workflows. We delved into a couple of NoMAD Login's specific parts, or "mechs"; __User Input__ and __Notify__, walking through one example of how to drive them during the enrolment and provisioning process. Below is an adaptation and simplification of the methods used in my university's environment. 

### Background stuff ###

A 45 minute conference slot is by no means enough time to cover every aspect of provisioning (the key word in the title is "Improve"!). I did assume some prerequieite knowledge from the audience, but if you're just embarking on this journey, welcome! The links below will help you get started. I will update the list with links to conference videos from MacADUK as they are made available. There were some awesome sessions that'll really help you get things going.

Lab Nauseum - Dawn Of The DEP (my talk from last year's Jamf Nation Roadshow and the precursor to this) - https://github.com/neilmartin83/Jamf-Nation-Roadshow-London-2018

If you aren‘t getting Apple push notifications - https://support.apple.com/en-gb/HT203609

2017: A Push Odyssey — Journey to the Center of APNS - https://www.youtube.com/watch?v=nXjEevMtwa4

Use Device Enrollment - https://support.apple.com/en-gb/HT204142

Apple Device Enrollment Program Guide - https://www.apple.com/education/docs/DEP_Guide.pdf

macOS Installation: Strange New World - https://scriptingosx.com/2018/05/macos-installation-strange-new-world/

### NoMAD Login AD (NoLoAD) ###

Grab NoLoAD here: https://gitlab.com/Mactroll/DEPNotify.

I focused on the 1.3.0 release (or rather, its release candidate - so there may be subtle differences from the stable one - live on the bleeding edge!).

Join the MacAdmins Slack: https://macadmins.herokuapp.com/ - check out the __#nomad-login__ channel, hang out with the developers and users, get involved with testing, ask questions, discuss and enjoy.

#### New mechs - Notify and User Input ####

NoLoAD includes some new shiny things that make it so much more than a login window replacement that creates local accounts from AD credentials. Although that is bloody awesome in itself! It could very much be considered as an extension to Apple's Setup Assistant, giving admins much-needed capabilities during DEP based enrolment.

__Notify__

This mech provides you with a nice "status screen" showing information about what's happening, with your company's branding added. This is DEPNotify but rolled into NoLoAD so it can run at the Login Window and don't have to be logged in! It's configured and driven in mostly the same way. See https://gitlab.com/Mactroll/DEPNotify for more details (and check out my presentation video and slides!).

__User Input__

This provides a framework for creating a dialog at the login window to accept input from the user in the form of text fields and drop-down menus. The results are saved to an XML formatted text file you can have your management tools read from during the provisioning process.

#### authchanger ####

I spoke about this thing called `authchanger` - an awesome little tool that easily and safely modifies the list of authentication mechanisms macOS uses when it boots and when a user logs in. It's included in the packaged version of NoLoAD  and we can use it to achieve a few goals:

* Replace Apple's login window with NoLoAD's one.
* Specify which of NoMAD's "mechs" you want to use and the order you want to use them.
* Reset everything back to using Apple's login window.

For more information, run `authchanger -help`

Examples:

* Replace Apple's login window with NoLoAD: `authchanger -reset -AD`
* Make NoLoAD start with Notify mech only `authchanger -reset -preLogin NoMADLoginAD:Notify`
* Make NoLoAD start with User Input then progress to Notify after User Input has been received (when the user clicks the button): `/usr/local/bin/authchanger -reset -preLogin NoMADLoginAD:UserInput NoMADLoginAD:Notify`


### DEP - Provision - Example.sh ###

In my example, this script is intended to be ran via a Policy that's triggered on "Enrolment Complete" (you could be fancy and trigger it via a self-destructing Launch Daemon etc to ensure it will re-run incase provisioning is interrupted and the Mac is restarted).

The policy should also install DEPNotify along with your branding image - in this script, the image is assumed to be in `/Library/Application Support/UEL/ux/UEL.png` (rename/replace or don't use so you get the default, as per your organisation).

The script makes use of Jamf's parameter functionality: https://www.jamf.com/jamf-nation/articles/146/script-parameters

- `$4` = Jamf Pro Server URL (excluding the port number - 8443 is assumed, edit the script if you use something else)
- `$5` = Username for the Jamf Pro Server account doing the API reads/writes (must have privileges to read and update Computers objects, as well as permission to update Users objects)
- `$6` = Password for the Jamf Pro Server account doing the API reads/writes

In order to automatically skip asking for user input if the computer record already exists with a name and role, the script reads from and populates these Extension Attributes to the Computer Record via the Jamf API (modify as appropriate for your org, or don't use them if you don't want this little bit of automation):

- Hostname (string)
- Computer Role (string)

We write the computer's hostname to our own `Hostname` Extension Attribute via the Jamf API during provisioning so it will persist when a Mac is erases with a clean install of macOS (because the actual Computer Name in the Jamf Computer Record changes to the default "iMac" etc value when the freshly re-provisioned Mac re-enrolls).

In my environment, the hostname determines which lab a Mac belongs in. So for a hostname of `DLEB285-12345`:

For example, the first part of the hostname denotes the computer lab, `DLEB285` and can be broken down/decoded as follows:

- `DL`: Campus code (Docklands)
- `EB`: Building code (East Building)
- `2`: Floor code (2nd Floor)
- `85`: Room code (Room Number 85)

The second part of the hostname `12345` is an asset number, used for inventory purposes.

Lab Smart Groups are populated based on the computer hostname and role, so for Macs in lab `DLEB285` we would use:

#### Smart Group: Lab DLEB285 ####

And/Or | Criteria | Operator | Value
--- | --- | --- | ---
--- | Computer Name | like | DLEB285
and | Computer Role | is | Student

This is specific to my environment but does give some insight into how we can easily create differnt Smart Groups for Macs by campus, building, floor and room.

For each software title, separate Smart Groups are populated based on whether said application (or sometimes package receipt) is present and whether the Macs are in the specific Lab Smart Groups where the software is needed:

#### Smart Group: Deploy Mozilla Firefox ####

And/Or | Criteria | Operator | Value
--- | --- | --- | ---
--- | Application Title | is not | Firefox.app
and ( | Computer Group | member of | Lab DLEB285
or | Computer Group | member of | Lab DLWB123 )

In this example, we would get Macs without Firefox that are in labs DLEB285 or DLWB123. Once a Mac in either of those labs has Firefox, it will leave this Smart Group.

For each software title, a separate Policy is created to install it. Each Policy is scoped to its corresponding Smart Group (above). These Policies must have an `Update Inventory` step included to ensure that Macs leave the scoped Smart Group as soon as they have the application installed.

The Policies all have the same custom trigger: `Deploy`. This means that you can deploy all the software a specific lab needs with a single command in the provisioning script: `jamf policy -event Deploy`.

It is possible to go further with version detection and/or using Jamf's patch management policies but that is beyond the scope of my presentation.