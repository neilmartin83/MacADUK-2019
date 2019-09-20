#!/bin/bash

## First run script following DEP enrolment
## Neil Martin, University of East London
# $4 = JSS URL incuding port number - e.g. https://yourjss.com:8443
# $5 = JSS account username for API access
# $6 = JSS account password for API access

# Set basic variables
osversion=$(/usr/bin/sw_vers -productVersion)
serial=$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F'"' '/IOPlatformSerialNumber/{print $4}')

# Function to add date to log entries
log(){
NOW="$(date +"*%Y-%m-%d %H:%M:%S")"
/bin/echo "$NOW": "$1"
}

# Logging for troubleshooting - view the log at /private/tmp/firstrun.log
/usr/bin/touch /private/tmp/firstrun.log
exec 2>&1>/private/tmp/firstrun.log

# Let's not go to sleep
log "Disabling sleep..."
/usr/bin/caffeinate -d -i -m -s -u &
caffeinatepid=$!

# Disable Automatic Software Updates during provisioning
log "Disabling automatic software updates..."
/usr/sbin/softwareupdate --schedule off

# Set Network Time
log "Configuring Network Time Server..."
/usr/sbin/systemsetup -settimezone "Europe/London"
/usr/sbin/systemsetup -setusingnetworktime on

# Copy our wallpaper over Mojave's default
/bin/cp "/Library/Application Support/UEL/branding/wallpaper.jpg" "/Library/Desktop Pictures/Mojave.heic"

# Check for existing Hostname extension attribute in JSS - if it's not there, we'll set up NoMAD Login with User Input mech, otherwise, we will proceed with Notify mech only!
log "Checking for existing Hostname and Role in JSS..."
eaxml=$(/usr/bin/curl "$4"/JSSResource/computers/serialnumber/"$serial"/subset/extension_attributes -u "$5":"$6" -H "Accept: text/xml")
computerName=$(/bin/echo "$eaxml" | /usr/bin/xpath '//extension_attribute[name="Hostname"' | /usr/bin/awk -F'<value>|</value>' '{print $2}')
computerRole=$(/bin/echo "$eaxml" | /usr/bin/xpath '//extension_attribute[name="Mac User Role"' | /usr/bin/awk -F'<value>|</value>' '{print $2}')

# Wait for the setup assistant to complete before continuing
log "Waiting for Setup Assistant to complete..."
loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}     ')
while [[ "$loggedInUser" == "_mbsetupuser" ]]; do
	/bin/sleep 5
	loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}     ')
done

# Let's continue
log "Setup Assistant complete, continuing..."

if [[ "$computerName" == "" ]] || [[ "$computerRole" == "" ]]; then
	log "Hostname or Role not set in JSS, proceeding to User Input..."

	# Quit Notify and proceed to UserInput mech
	/bin/echo "Command: Quit" >> /var/tmp/depnotify.log
	/bin/sleep 5
	/bin/echo "Command: Image: "/Library/Application Support/UEL/branding/logo-prov.png"" > /var/tmp/depnotify.log
	/bin/echo "Command: MainTitle: Please wait a moment..."  >> /var/tmp/depnotify.log
	/bin/echo "Command: MainText: " >> /var/tmp/depnotify.log
	/bin/echo "Status: Please wait..." >> /var/tmp/depnotify.log

	# Wait for the user data to be submitted...
	while [[ ! -f /var/tmp/userinputoutput.txt ]]; do
		log "Waiting for user data..."
		/bin/sleep 5
	done

	log "User data submitted, continuing setup..."

	# Let's read the user data into some variables...
	computerName=$(/usr/libexec/plistbuddy /var/tmp/userinputoutput.txt -c "print 'Computer Name'")
	computerRole=$(/usr/libexec/plistbuddy /var/tmp/userinputoutput.txt -c "print 'Computer Role'")

	# Update Hostname and Computer Role in JSS
	# Create xml
	/bin/cat << EOF > /var/tmp/name.xml
<computer>
    <extension_attributes>
        <extension_attribute>
            <name>Hostname</name>
            <value>$computerName</value>
        </extension_attribute>
    </extension_attributes>
</computer>
EOF
	## Upload the xml file
	/usr/bin/curl -sfku "$5":"$6" "$4"/JSSResource/computers/serialnumber/"$serial" -H "Content-type: text/xml" -T /var/tmp/name.xml -X PUT
	# Create xml
	/bin/cat << EOF > /var/tmp/role.xml
<computer>
    <extension_attributes>
        <extension_attribute>
            <name>Mac User Role</name>
            <value>$computerRole</value>
        </extension_attribute>
    </extension_attributes>
</computer>
EOF
	## Upload the xml file
	/usr/bin/curl -sfku "$5":"$6" "$4"/JSSResource/computers/serialnumber/"$serial" -H "Content-type: text/xml" -T /var/tmp/role.xml -X PUT
fi

# Carry on with the setup...

# Change DEPNotify title and text...
/bin/echo "Command: MainTitle: Setting things up..."  >> /var/tmp/depnotify.log
if [[ $computerRole == "Student" ]]; then
	/bin/echo "Command: MainText: Please wait while we set this Mac up with the software and settings it needs. This may take a few hours. We'll restart automatically when we're finished. \n \n Role: "$computerRole" Mac \n Computer Name: "$computerName" \n macOS Version: "$osversion""  >> /var/tmp/depnotify.log
else
	/bin/echo "Command: MainText: Please wait while we set this Mac up with the software and settings it needs. This may take up to 20 minutes. We'll restart automatically when we're finished. \n \n Role: "$computerRole" Mac \n Computer Name: "$computerName" \n macOS Version: "$osversion""  >> /var/tmp/depnotify.log
fi

log "Initiating Configuration..."

# Time to set the hostname...
/bin/echo "Status: Setting computer name" >> /var/tmp/depnotify.log
log "Setting hostname to "$computerName"..."
/usr/local/bin/jamf setComputerName -name "$computerName"

# Bind to AD
log "Binding to Active Directory..."
/bin/echo "Status: Binding to Active Directory..." >> /var/tmp/depnotify.log
/usr/local/bin/jamf policy -event BindAD

# Deploy policies for all Macs
log "Running software deployment policies..."
/bin/echo "Status: Installing software, please wait..." >> /var/tmp/depnotify.log
/usr/local/bin/jamf policy -event Deploy
log "Software deployment policies done running"

# Run a recon, set asset tag and room number - this takes the hostname e.g. ABCD123-12345 and splits it at the '-' character to extracpolate the room (first field) and asset number (second field)
/bin/echo "Status: Updating inventory..." >> /var/tmp/depnotify.log
log "Setting variables for asset tag and room..."
assetno=$(/bin/echo "$computerName" | /usr/bin/cut -d '-' -f 2)
room=$(/bin/echo "$computerName" | /usr/bin/cut -d '-' -f 1)
log "Running recon..."
/usr/local/bin/jamf recon -assetTag "$assetno" -room "$room"

# Run a Software Update - this calls a custom policy trigger that has a Software Update payload configured
log "Running Apple Software Update..."
/usr/local/bin/jamf policy -event DeploySUS

# Finishing up - tell the provisioner what's happening

/bin/echo "Command: MainTitle: All done!"  >> /var/tmp/depnotify.log
/bin/echo "Command: MainText: This Mac will restart shortly and you'll be able to log in. \n \n If you need any assistance, please contact the UEL IT Service Desk. \n \n Telephone: 020 8223 2468 \n Email: servicedesk@uel.ac.uk"  >> /var/tmp/depnotify.log
/bin/echo "Status: Restarting, please wait..." >> /var/tmp/depnotify.log

# Reset login window authentication mech to Apple
log "Resetting Login Window..."
/usr/local/bin/authchanger -reset

# Kill caffeinate and restart with a 2 minute delay
log "Decaffeinating..."
log "Restarting in 2 minutes..."
kill "$caffeinatepid"
/sbin/shutdown -r +2 &

log "Done!"
